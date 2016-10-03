* copy emacs binary and files
  ssh $target_machine mkdir ~/local/share/
  rsync -ave ssh ~/local/share/ $target_machine:~/local/share/
  ssh $target_machine mkdir ~/local/bin/
  rsync -ave ssh ~/local/bin/ $target_machine:~/local/bin/
  ssh $target_machine mkdir ~/local/libexec/
  rsync -ave ssh ~/local/libexec/ $target_machine:~/local/libexec/
* install aspell deps
  brew install aspell
* install nodejs deps
  - on target_machine
    curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.32.0/install.sh | bash
    or rsync -ave ssh ~/.nvm/ $target_machine:~/.nvm/
* install SCBL deps
  curl -O http://nchc.dl.sourceforge.net/project/sbcl/sbcl/1.2.11/sbcl-1.2.11-x86-64-darwin-binary.tar.bz2
  cd sbcl-1.2.11-x86-64-darwin && sh install.sh
* install R deps
  brew tap homebrew/science
  brew install Caskroom/cask/xquartz
  brew install r  
* clone ~etc/el
  mkdir -p ~/etc/
  git clone https://github.com/bartuer/dot-emacs.git el
  - on target machine
    cd ~/etc/el/vendor && npm install
* link .emacs.el
  ln -s ~/etc/el.emacs.el
* copy .bashrc
  # notice to update SDKROOT
  scp ~/.bashrc_osx $target_machine:~/.bashrc
