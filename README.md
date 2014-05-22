sheepdog-utils
==============

Collection of scripts to simplify sheepdog installation and execution.

What do they do?
================

install.sh is going to install the required packages to build sheepdog and a
recent qemu version.
It also takes care of changing some default system parameters.

assistant.sh will ask you some questions to properly run sheep daemon for you.

Requirements 
============

3 or more nodes with Debian wheezy x86_64.
One or more devices per node to dedicate to sheepdog.

Before running this script
==========================

Setup your network.
Add 'deb-src' repository.
Format the sheepdog dedicated devices; add them to you /etc/fstab and mount
them.
(Remember to use 'user_xattr' option for kernels < 3.12).




