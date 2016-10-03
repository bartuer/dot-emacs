# echo "Setup Git"
# git config --global user.email "bazhou@microsoft.com"
# git config --global user.name "Bartuer Zhou"
# git config --global push.default simple
# echo "Update yum"
# sudo yum update;

# echo "Install ASpell Package"
# # install aspell
# sudo yum install aspell aspell-en.x86_64 -y;

# echo "Install SBCL CommonLisp Package"
# #install SBCL
# sudo yum install sbcl -y

# echo "Install R Package" 
# #install R
# sudo yum install R -y

# echo "Install JS/NodeJs/npm (via nvm)"
# # install nvm/choose nodejs
# curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.32.0/install.sh | bash

# export NVM_DIR="/home/bazhou/.nvm" && [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

# nvm install 6.0 && nvm use 6.0

# # install gulp
# npm install -g gulp

echo "Clone Emacs for dot-emacs"
# clone emacs package
mkdir -p ~/etc
cd ~/etc
git clone https://github.com/bartuer/dot-emacs.git el

echo "Compile Emacs"
# compile/install emacs
# sudo yum install ncurses-devel.x86_64 xclip -y
# mkdir -p ~/local/src
# cd ~/local/src
# curl -O https://ftp.gnu.org/gnu/emacs/emacs-24.5.tar.gz
# tar -xzf emacs-24.5.tar.gz 
cd emacs-24.5
cp ~/etc/el/install/emacs.config.log configure.sh
chmod +x configure.sh
./configure.sh
make && make install

echo "Post Configure for Emacs"
cp ~/etc/el/install/pbcopy.xlicp.sh ~/local/bin
ln -s ~/local/share/emacs/24.5 ~/local/share/emacs/current

# install emacs js package
cd ~/etc/el/vendor
npm install

#link .emacs.el
cd ~
ln -s ~/.emacs.el ~/etc/el/.emacs.el

#add bashrc shortcut
cat etc/el/install/bashrc_linux.sh >> ~/.bashrc
source ~/.bashrc

echo "type ed to verify emacs installation"