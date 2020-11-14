echo "Setup Git"
git config --global user.email "bazhou@microsoft.com"
git config --global user.name "Bartuer Zhou"
git config --global push.default simple
echo "Update apt"
sudo apt-get update

echo "Install ASpell Package"
sudo apt-get install aspell aspell-en gnutls-dev -y

echo "Install SBCL CommonLisp Package"
sudo apt-get install sbcl -y

echo "Install R Package" 

sudo apt-get install r-base -y

echo "Install JS/NodeJs/npm (via nvm)"
curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.32.0/install.sh | bash

export NVM_DIR="/home/$(whoami)/.nvm" && [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

nvm install 6.0

nvm use 6.0

# install gulp
npm install -g gulp

echo "Clone Emacs for dot-emacs"
# clone emacs package
mkdir -p ~/etc
cd ~/etc
git clone https://github.com/bartuer/dot-emacs.git el

echo "Compile Emacs"
# compile/install emacs
sudo apt-get install libncurses5-dev xclip -y
mkdir -p ~/local/src
cd ~/local/src
curl -O https://ftp.gnu.org/gnu/emacs/emacs-25.3.tar.gz
tar -xzf emacs-25.3.tar.gz 
cd ~/local/src/emacs-25.3
cp ~/etc/el/install/emacs.config.log configure.sh
chmod +x configure.sh
./configure.sh
make -j && make install

echo "Post Configure for Emacs"
mkdir -p ~/local/bin/
cp ~/etc/el/install/pbcopy.xlicp.sh ~/local/bin/pbcopy
cp ~/etc/el/install/killemacs ~/local/bin/killemacs
cp ~/etc/el/install/quote0 ~/local/bin/quote0
sudo cp ~/etc/el/install/killemacs /usr/bin
sudo cp ~/etc/el/install/quote0 /usr/bin
sudo cp ~/etc/el/install/pbcopy.xlicp.sh ~/local/bin/pbcopy

ln -s ~/local/share/emacs/25.3 ~/local/share/emacs/current

# install emacs js package
cd ~/etc/el/vendor
npm install

#link .emacs.el
cd ~
ln -s ~/etc/el/.emacs.el ~/.emacs.el 

#add bashrc shortcut
cat ~/etc/el/install/bashrc_linux.sh >> ~/.bashrc
source ~/.bashrc

echo "type ed to verify emacs installation"