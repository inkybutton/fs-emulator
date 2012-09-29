fs-emulator
===========

A simple filesystem emulator written in Ruby 1.9. Licensed in MIT license.

For a University assignment I created a filesystem within Ruby that has support for directories, files, links and history. A command prompt was also created for a user to interact with it. It has Unix-style file paths.

I learnt Ruby from the scratch for the project, which is not very difficult with prior experience with dynamic languages. I also experimented with not using classes to structure code, as seen in some other languages. While Ruby has some nice features and syntactic sugar, I found its (lack of) backwards- and forwards-compatibility to be a downside to the language. The way anonymous functions work (Procs, blocks, etc.) can also improve. The project does not work in Ruby 1.8.*

Usage
==========
It's easy to run the application. Simply get Ruby 1.9 (written on 1.9.3p194). Then
1. Download.
2. Make fs.rb executable (chmod u+x fs.rb)
3. ./fs.rb

The application gives no prompt, but you can enter these commands, and hit return for them to be executed. You can also redirect a file with commands for them to be executed - e.g. `./fs.rb < commands.txt`.

Command List
------------
* `home` - Returns to filesystem root directory.
* `listfiles` - Lists files and directories in the current directory. Gives the size of the file or directory.
* `enter <pathname>` - Enters the directory with the given _pathname_.
* `mkdir <pathname>`- Creates a new directory, and makes a link to it at the given _pathname_.
* `create <pathname>` - Creates a new file, and makes a link to it at the given _pathname_.
* `append <string> <pathname>` - Modifies the file with the given _pathname_, and adds the content of the _string_. The string should be surrounded by quotation marks. e.g. `append "Some new content!" /mytext.txt`.
* `link <newlinkpath> <oldlinkpath>` - Creates a link to a file or a directory - this is similar to a hard link in Unix systems. e.g. `link /mydir /existingdir` creates a link to /existingdir from /mydir, so the directory linked by /existingdir can be accessed from /mydir.
* `move <srcpath> <destpath>` - Moves link from srcpath to destpath.
* `delete <pathname>` - deletes the link to a file or directory at pathname. If the file or directory has no other links, the file/directory is deleted.
* `hist <pathname>` - Shows the modification history of a file or directory, along with the version number.
* `restore <versionnumber> <pathname>` - Reverts the content of the file or directory specified by pathname from an older version. The versionnumber can be looked up in `hist`.

Extending/Adapting fs-emulator
===========
Wow, really? Well, I'm glad it may be useful to you. The project is divided into entities(files and directories), links, persistence functions, and the shell.
`MemoryNFS` is a in-memory implementation of persistence functions, which takes entities and stores them in memory. You can implement a disk-based version or other persistent mechanisms by implementing `update-entity!`, `deref`, and `resolve`. Code might need some refactoring for it to work.
