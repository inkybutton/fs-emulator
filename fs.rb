#! /usr/bin/ruby
# Filesystem Emulator with Hard Links (TM)

#Copyright (c) 2012 Noel Zeng

#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Written with Ruby 1.9.3

module NFSEntity
  # An entity is a file managed by the filesystem.
  # It has a notion of versions of the entity.
  # A new version is created when, in the case of a file,
  # the content of a file changes or in the case of a directory,
  # the directory has new files or directories in it. This means
  # a versioning filesystem can be supported.
  # Entity does not provide means for persisting
  # states. This means there can be multiple
  # persistent backends. See MemoryNFS for a
  # memory-based implementation.

  def entity(type,versions,refs)
    {:versions => versions,:type => type,:refs => refs}
  end

  def new_entity(type,default_content)
    entity(type,[default_content],[])
  end

  def nil_entity
    new_entity(:nil)
  end

  def refs(entity)
    entity[:refs]
  end
  
  def entity?(obj)
    obj.has_key?(:versions) && obj.key?(:type)
  end

  def orphan?(entity)
    entity[:refs] == 0
  end

  def get_version(entity,version_num)
    if (version_num <= entity[:versions].length-1)
      entity[:versions][version_num]
    else
      nil
    end
  end

  def current(entity)
    get_version(entity,current_version_num(entity))
  end

  def from_version(entity,version_num)
    entity[:versions].slice(version_num..current_version_num(entity))
  end

  def current_version_num(entity)
    entity[:versions].length - 1
  end
end

module NFSLink
include NFSEntity
# A link is a binding between an entity and a name, as well
# the version of the entity when the link was created.
# The entity may be dereferenced by using deref, deref_current,
# or deref_all.

  def name(link)
    link[:name]
  end

  def version(link)
    link[:starting_version]
  end

  def deref(link)
    link[:referred]
  end

  # Returns the current version of the entity being
  # referenced.
  def deref_current(link)
    current(deref(link))
  end

  # Returns versions of the entity that have been
  # created since this link was created.
  def deref_all(link)
    from_version(deref(link),version(link))
  end

  def link(name,entity,root)
    {:name => name, :referred => entity, :starting_version => current_version_num(entity),:root => root}
  end

  def new_link(name,entity)
    {:name => name, :referred => entity, :starting_version => current_version_num(entity),:root => nil}
  end

  def nil_link
    {:name => "", :referred => nil, :starting_version => 0,:root => nil}
  end

  def link?(obj)
    obj.key?(:referred) && obj.key?(:name) && obj.key?(:starting_version)
  end

end

module NFSFile
  include NFSEntity
  def file(content,refs,root)
    entity(:file,content,refs)
  end

  def empty_file
    new_entity(:file,"")
  end

  def append_file(content)
    Proc.new{|old_content| old_content + content}
  end

  def file?(obj)
    entity?(obj) && obj[:type] == :file
  end

  def size(file)
    current(file).length
  end
end

module NFSDirectory
  # A directory is an entity that contains a collection
  # of links.
  include NFSEntity,NFSLink
  
  def directory(links,refs)
    entity(:dir, links,refs) 
  end

  def empty_directory
    new_entity(:dir,{})
  end

  def dir_size dir
    size = 0
    current(dir).each do |l,v|
      size = size + l.length + 1
    end
    size
  end

   def to_abs_path(parent_path,local_name)
     if root?(parent_path)
       parent_path + local_name
     elsif root?(local_name)
       local_name
     else
       parent_path + "/" + local_name
     end
   end

  def parent(abs_path)
    path = abs_path.split("/")
    path[0..path.length-2].join("/")+"/"
  end

  def local_name (abs_path)
    abs_path.split("/").last
  end
  
  def rm_from_dir(link)
    Proc.new{|dir|
      dir.reject do |k,v|
        k == name(link)
      end}
  end

  def add_to_dir(link)
    Proc.new{|links| 
      links.merge({name(link) => link})}
  end

  def directory?(obj)
    entity?(obj) && obj[:type] == :dir
  end

  def abs_path?(path)
    path[0] == "/"
  end
  
  def root?(path)
    path.length == 1 && path[0] == "/"
  end

end

module MemoryNFS
  include NFSEntity,NFSFile,NFSDirectory,NFSLink

  # Updates and persists the entity state, creating a new version.
  # @entity - Entity to be updated
  # @updatefn - A Proc that takes the current latest version,
  # and returns a new entity. The new entity becomes
  def update_entity!(entity,updatefn)
    current_version = current(entity)
    proposed_new_version = updatefn.call(current_version)
    if not(proposed_new_version === current_version)
      entity[:versions].push proposed_new_version
    end
    entity
  end

  def replace_entity!(entity,newval)
    update_entity!(entity,Proc.new{|x| newval})
  end

   def _link!(link)
     e = deref(link)
     e[:refs].push link
     link
   end

   def _unlink!(link)
     e = deref(link)
     e[:refs].delete_if do |l|l.equal? link end
     e
   end

   def _set_root!(root,link)
     if directory? root
       link[:root] = root
     else
       raise Exception.new("Root of an entity must always be a directory.")
     end
   end

   def store!(fs,obj,parent_dir)
     if link? obj
       update_entity!(deref(parent_dir),add_to_dir(obj))
       _link!(obj)
       _set_root!(deref(parent_dir),obj)
       fs
     else
       raise Exception.new("Expected a link.")
     end
   end

   def resolve(fs,path)
     if abs_path? path
       if root? path
         fs[:tree]
       else
         path_segs = path.split("/")
         resolve_recursively(fs[:tree],path_segs[1..path_segs.length-1])
       end
     end
   end
   
   def resolve_recursively(dir,path)
     dir = deref_current(dir)
     if dir.key? path.first
       newdir = dir[path.first]
       if path.length == 1
         newdir
       else
         resolve_recursively(newdir,path[1..path.length-1])
       end
     else
       nil
     end
   end

   # Since this implementation is memory-based, the entity
   # will be deleted by the garbage collector when there are
   # no references from the tree.

   def delete!(link)
     update_entity!(link[:root],rm_from_dir(link))
     _unlink!(link)
   end
   
   def purge!(entity)
     entity[:refs].each do |r| 
       # BUG Calling delete! while iterating inside the
       # collection seems to leave one item not deleted.
       # Workaround is to clear :refs.
       update_entity!(r[:root],rm_from_dir(r))
     end
     entity[:refs] = []
   end
   
   def empty_mfs
     root = new_link("/",empty_directory)
     _link!(root)
     {:tree => root}
     
   end
 end
 
 module Repl
   
   def repl_loop (prompt,interpretfn,execfn,initial_state)
     state = initial_state
     ARGF.each do |response|
       if response == "quit"
         exit
       elsif response == "\n"
         next
       elsif response.start_with? "\""
         puts response[1..response.length-3]
         next
       end
       state = execfn.call(interpretfn.call(response),state)
     end
   end

   def get_abs_path(cur_path,new_path)
     if abs_path? new_path
       new_path
     else
       to_abs_path(cur_path,new_path)
     end
   end

   def create!(fs,abs_path,entity)
     parent_dir = resolve(fs,parent(abs_path)) # Gets the absolute path, then only the parent part.
     linked_ent = new_link(local_name(abs_path),entity)
     store!(fs,linked_ent,parent_dir)
   end

  include MemoryNFS
 
  def start
    # @current_path = "/"
    # @fs = empty_mfs
    state = {:current_path => "/", :fs => empty_mfs}
    @cmdfns =
      {"home" => Proc.new {|opts,s| s[:current_path] = "/"
      s},
      "enter" => Proc.new {|opts,s| 
        if abs_path? opts[0]
          s[:current_path] = opts[0]
        else
          if root? s[:current_path]
            s[:current_path] = s[:current_path] + opts[0]
          else
            s[:current_path] = s[:current_path] + "/" + opts[0]
          end
        end
        s
      },
      "listfiles" => Proc.new{|opts,s|
        cur_dir = deref_current(resolve(s[:fs],s[:current_path]))
        puts("=== "+s[:current_path]+" ===")
        entry_template = "%-20s%2s%10s"
        list = cur_dir.map do |k,v|
          x = deref(v)
          name = k
          dir_flag = ""
          size = ""
          if directory? x
            size = dir_size x
            dir_flag = "d"
          else
            size = size x
          end
          [name,dir_flag,size]
        end
        list.sort! do |l,r|
          l[0] <=> r[0]
        end
        list.each do |l|
          puts entry_template % l
        end
        s
      },
      "mkdir" => Proc.new{|opts,s|
        abs_path = get_abs_path(s[:current_path],opts[0])
        create!(s[:fs],abs_path,empty_directory)
        s
      },
      "show" => Proc.new {|opts,s|
        path = get_abs_path(s[:current_path],opts[0])
        file = deref_current(resolve(s[:fs],path))
        puts file
        s
      },
      "append" => Proc.new{|opts,s|
        # TODO Fix interpreter code to split the output correctly.
        # i.e. interpret a quotation-mark surrounded sentence as one option.
        text = opts[0..opts.length-2].join(" ")
        text = text[1,text.length-2]
        path = get_abs_path(s[:current_path],opts.last)
        file = deref(resolve(s[:fs],path))
        update_entity!(file,append_file(text))
        s
      },
      "create" => Proc.new{|opts,s|
        abs_path = get_abs_path(s[:current_path],opts[0])
        create!(s[:fs],abs_path,empty_file)
        s
      },
      "link" => Proc.new{|opts,s|
        new_link_path = get_abs_path(s[:current_path],opts[0])
        existing_lp = get_abs_path(s[:current_path],opts[1])
        create!(s[:fs],new_link_path,deref(resolve(s[:fs],existing_lp)))
        s
      },
      "delete" => Proc.new{|opts,s|
        path = get_abs_path(s[:current_path],opts[0])
        link_to_del = resolve(s[:fs],path)
        delete! link_to_del
        s
      },
      "deleteall" => Proc.new{|opts,s|
        path = get_abs_path(s[:current_path],opts[0])
        purge! deref(resolve(s[:fs],path))
        s
      },
      "hist" => Proc.new{|opts,s|
        path = get_abs_path(s[:current_path],opts[0])
        link = resolve(s[:fs],path)
        history = deref_all(link)
        puts("History for "+name(link))
        puts("Entity version at link creation: "+version(link).to_s)
        history.each_index do |idx| puts("Ver "+idx.to_s+": "+history[idx]) end
        s
      },
      "move" => Proc.new{|opts,s|
        old_link = resolve(s[:fs],get_abs_path(s[:current_path],opts[0]))
        new_link_path = get_abs_path(s[:current_path],opts[1])
        create!(s[:fs],new_link_path,deref(old_link))
        delete! old_link
        s
      },
      "restore" => Proc.new{|opts,s|
        version = opts[0].to_i
        path = get_abs_path(s[:current_path],opts[1])
        link = resolve(s[:fs],path)
        new_ver = get_version(deref(link),version)
        if new_ver != nil
          replace_entity!(deref(link),new_ver)
        else
          puts "Invalid version number."
        end
        s
      }}
    
    repl_loop("Command?",
              Proc.new{|response| 
                r = response.split(" ")
                {:command => r.first,:options => r[1..r.length-1]}},
              Proc.new{|command,state|
                if @cmdfns.key? command[:command]
                  @cmdfns[command[:command]].call(command[:options],state)
                else
                  puts "Command not understood."
                  state
                end
              },state)
  end

end
include Repl
start
