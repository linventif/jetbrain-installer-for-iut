#!/bin/bash

path="/var/tmp/$USER"
desktop_entry_path="$HOME/.local/share/applications"
desktop_entry_auto_startup_path="$HOME/.config/autostart"
config_file="$HOME/.webstorm-installer"

script_name=`basename "$0"`
script_dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
echo $script_dir

desktop_content_startup="[Desktop Entry]
Name=Install WebStorm
GenericName=Script permettant d'installer WebStorm
Exec=sh -c \"NOTIFY=1 $script_dir/$script_name install 2>&1 > $HOME/.webstorm-installer-auto-startup.log\"
Terminal=false
Type=Application
X-GNOME-Autostart-enabled=true"

# Valeurs par défaut des variables du fichier de config
# Je remets les valeurs par défaut ici au cas où un utilisateur supprimerait des lignes du fichier de config
KEEP_TAR_GZ_FILE=0
TAR_GZ_PATH=$script_dir

mkdir -p $path

# Configure l'application
setup() {
    ask_to_keep_tar_gz_file
    echo
    cat <<-EOF > $config_file
    KEEP_TAR_GZ_FILE=$KEEP_TAR_GZ_FILE
    EOF

    echo
    echo "La configuration a été sauvegardée."
}

# Récupère l'entrée utilisateur pour savoir si il faut garder le fichier tar.gz
ask_to_keep_tar_gz_file() {
    echo "Le script permet de garder le fichier tar.gz qui contient les binaires du logiciel dans votre dossier personnel."
    echo "Ce fichier tar.gz pourra être modifié par le script quand il y aura des nouvelles mises à jour."
    echo "Les installations sur d'autres postes seront plus rapides, et vous n'aurez pas besoin d'internet pour faire l'installation."
    echo "Cependant, le fichier prendra de la place sur votre quota."
    printf "Voulez-vous garder le fichier tar.gz sur votre dossier personnel? y/N "
    read_entry

    case $answer in
        y|yes|o|oui) KEEP_TAR_GZ_FILE=1 ;;
        *) KEEP_TAR_GZ_FILE=0 ;;
    esac
}

# Installe WebStorm en décompressant un fichier .tar.gz et en ajoutant un fichier .desktop
install () {
    # On charge la configuration
    # Si le script n'est pas configuré on le redirige vers la commande setup
    [[ -f "$config_file" ]] && source $config_file || setup

    get_tar_gz_path $@
    extract_tar_gz
    [[ $is_downloaded == true && $KEEP_TAR_GZ_FILE == 0 ]] && delete_tar_gz
    add_desktop_entry
    exit 0
}

# Désinstalle WebStorm
remove () {
    echo "Supression fichiers WebStorm"
    rm -rf $path/webstorm 2> /dev/null
    echo "Suppression .desktop"
    rm $desktop_entry_path/webstorm.desktop 2> /dev/null
    rm $desktop_entry_auto_startup_path/install_webstorm.desktop 2> /dev/null
}

# Télécharge ou récupère le fichier .tar.gz contenant les fichiers de WebStorm
get_tar_gz_path () {
    if [[ $# == 1 ]]
    then
        use_user_tar_gz $1
    else if [[ $force_install == true ]]
    then
        use_downloaded_tar_gz
    else
        download_if_useful
    fi
    fi
}

# Installe WebStorm quand c'est utile (installation ou mise à jour)
download_if_useful() {
    get_installed_version_number
    get_latest_version_number

    [[ $installed_version_number != -1 ]] && echo "Version actuelle de l'installation: ($installed_version_number)"

    if [[ $installed_version_number != $latest_version_number ]]
    then
        if [[ $installed_version_number != -1 ]]
        then
            echo "Une nouvelle version de WebStorm est disponible! ($latest_version_number)"
            notify "Mise à jour de WebStorm..."
        else
            notify "Installation de WebStorm..."
        fi
        use_downloaded_tar_gz
    else
        no_need_to_update
    fi
}

# Télécharge le tar.gz depuis le site de WebStorm
use_downloaded_tar_gz () {
    mkdir -p $path

    if [ -f $script_dir/webstorm-*-download.tar.gz ]
    then
        use_already_downloaded_tar_gz
    else
        if [[ $KEEP_TAR_GZ_FILE == 1 ]]
        then
            get_latest_version_number
            tar_gz_path=$TAR_GZ_PATH/webstorm-$latest_version_number-download.tar.gz
        else
            tar_gz_path=$path/webstorm.tar.gz
        fi
        download_latest_version $tar_gz_path
        is_downloaded=true
    fi
}

use_already_downloaded_tar_gz() {
    current_tar_gz=$(ls $script_dir/webstorm-*-download.tar.gz | head -n 1)
    current_version=$(echo $current_tar_gz | cut -d - -f 2 )
    get_latest_version_number
    if [[ $current_version == $latest_version_number ]]
    then
        tar_gz_path=$current_tar_gz
        is_downloaded=false
    else
        rm $current_tar_gz
        tar_gz_path=$script_dir/webstorm-$latest_version_number-download.tar.gz
        download_latest_version $tar_gz_path
        is_downloaded=true
    fi
}

# Récupère l'entrée utilisateur
read_entry() {
    read answer
    answer=$(echo $answer | tr '[:upper:]' '[:lower:]')
}

# Envoie un message d'information qui indique que la dernière version a déjà été installée
no_need_to_update () {
    echo "La dernière version de WebStorm est déjà installée!"
    echo "Vous pouvez utiliser le paramètre -f (--force) pour forcer la réinstallation"
    exit 0
}

# Récupère le fichier .tar.gz que l'utilisateur donne en paramètre
use_user_tar_gz () {
    tar_gz_path=$1
    check_path_validity
    is_downloaded=false
}

# Télécharge la dernière version de WebStorm
# Si il n'y a pas internet, un message d'erreur s'affiche
download_latest_version () {
    echo "Téléchargement de la dernière version de WebStorm..."
    curl -L "https://download.jetbrains.com/product?code=WS&latest&distribution=linux" -o $tar_gz_path
    if [[ $? != 0 ]]
    then
        printf "Impossible de télécharger la dernière version de WebStorm, essayez de fournir un fichier .tar.gz\n'$script_name install <filename>.tar.gz'\n"
        notify "Téléchargement impossible, consultez les logs"
        exit 1
    fi
}

# Vérifie si le fichier donné en paramètre est valide
# Si il y a une erreur, la fonction affiche l'erreur et le programme s'arrête
check_path_validity () {
    if [ -d $tar_gz_path ]
    then
        echo "$tar_gz_path est un dossier, vous devez fournir un fichier compressé (.tar.gz)"
        exit 2
    fi

    if [ ! -f $tar_gz_path ]
    then
        echo "Le fichier $tar_gz_path n'existe pas"
        exit 3
    fi

    if !(file $tar_gz_path | grep -q compressed)
    then
        echo "Le fichier est invalide, veuillez fournir un fichier compressé (.tar.gz)"
        exit 4
    fi
}

# Extrait le fichier .tar.gz avec le nom de dossier "webstorm"
extract_tar_gz () {
    mkdir -p $path
    echo "Extraction de WebStorm à partir du fichier $tar_gz_path..."
    tar -xf $tar_gz_path -C $path

    if [[ $? != 0 ]]
    then
        echo "Erreur dans l'extraction du fichier"
        notify "Erreur dans l'extraction du fichier, consultez les logs"
        exit 4
    else
        echo "Extraction terminée!"
    fi

    rm -rf $path/webstorm 2> /dev/null
    mv $path/WebStorm* $path/webstorm # Enlève le numéro de version à la fin du dossier
    notify "Installation terminée!"
}

# Ajoute le fichier .desktop pour pouvoir lancer l'application depuis le menu d'applications
add_desktop_entry () {
    mkdir -p $desktop_entry_path
    cat <<-EOF > $desktop_entry_path/webstorm.desktop
    [Desktop Entry]
    Version=1.0
    Type=Application
    Name=WebStorm
    Comment=The smartest JavaScript IDE
    Exec=$path/webstorm/bin/webstorm.sh %f
    Icon=$path/webstorm/bin/webstorm.svg
    Terminal=false
    StartupNotify=true
    StartupWMClass=jetbrains-webstorm
    Categories=Development;IDE;JavaScript;
    EOF
    echo "$desktop_content_launch"
    echo "Raccourci de l'application créé (vous devez peut-être redémarrer votre session pour voir le changement)"
}

# Supprime le fichier .tar.gz
delete_tar_gz () {
    rm $tar_gz_path
    echo "Fichier .tar.gz supprimé"
}

# Récupère le numéro de version de WebStorm qui est installée
get_installed_version_number () {
    installed_version_number=-1
    buildtxt_path=$path/webstorm/build.txt
    if [ -f $buildtxt_path ]
        then installed_version_number=$(cat $buildtxt_path | cut -d '-' -f 2)
    fi
}

# Récupère le dernier numéro de version de WebStorm
# Si il y a une erreur c'est égal à -1
get_latest_version_number () {
    latest_version_number=$(curl -s "https://data.services.jetbrains.com/products/releases?code=WS&latest=true&type=release" | grep -o '"build":"[^"]*' | grep -o '[^"]*$')
    if [ $? != 0 ]
    then
        echo "Aucune connexion internet, impossible de récupérer le numéro de la dernière version"
        printf "Essayez de fournir un fichier .tar.gz\n'$script_name install <filename>.tar.gz'\n"
        notify "Aucune connexion internet"
        exit 1
    fi
}

# Affiche une notification zenity quand le script est lancé automatiquement
notify () {
    [[ $NOTIFY == 1 ]] && zenity --notification --window-icon="info" --text="$1"
}

# Affiche une aide de toutes les commandes
usage () {
    echo "Usage: ./$script_name [ OPTION ] COMMANDE [ ARGUMENT ]"
    echo
    echo "Outil d'installation de l'IDE WebStorm sur les machines de l'IUT"
    echo
    echo "OBJECTS:"
    echo "  install                         Installe WebStorm dans le dossier $path"
    echo "  remove                          Désinstalle WebStorm (ne supprime pas les fichiers de configuration)"
    echo
    echo "OPTIONS:"
    echo "  -f                              Force la réinstallation de WebStorm"
    echo "  -h                              Donne cette liste d'aide"
    exit 0
}

while getopts ":f :d" option; do
    case "${option}" in
        f)
            force_install=true
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if declare -f "$1" > /dev/null
then
  "$@"
else
  usage
fi