#!/bin/bash

path="/var/tmp/$USER"
desktop_entry_path="$HOME/.local/share/applications"
desktop_entry_auto_startup_path="$HOME/.config/autostart"
config_file="$HOME/.intellij-installer"

script_name=`basename "$0"`
script_dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
echo $script_dir

desktop_content_startup="[Desktop Entry]
Name=Install IntelliJ IDEA
GenericName=Script permettant d'installer IntelliJ IDEA
Exec=sh -c \"NOTIFY=1 $script_dir/$script_name install 2>&1 > $HOME/.intellij-installer-auto-startup.log\"
Terminal=false
Type=Application
X-GNOME-Autostart-enabled=true"

# Valeurs par défaut des variables du fichier de config
# Je remets les valeurs par défaut ici au cas où un utilisateur supprimerait des lignes du fichier de config
KEEP_TAR_GZ_FILE=0
EDITION=IC
TAR_GZ_PATH=$script_dir

mkdir -p $path

# Configure l'application
setup() {
    ask_to_keep_tar_gz_file
    echo
    ask_for_edition
    echo
    ask_for_launch_on_startup

    cat <<-EOF > $config_file
	KEEP_TAR_GZ_FILE=$KEEP_TAR_GZ_FILE
	EDITION=$EDITION
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

# Récupère l'entrée utilisateur pour savoir si il faut lancer le script au démarrage de la session
ask_for_launch_on_startup() {
    printf "Voulez-vous lancer le script au démarrage de la session? Y/n "
    read_entry
    echo
    case $answer in
        n|no|non) do_not_run_script_on_startup ;;
        *) run_script_on_startup ;;
    esac
}

# Récupère l'entrée utilisateur pour choisir l'édition d'IntelliJ à installer
ask_for_edition() {
    echo "Quel édition d'IntelliJ voulez-vous utiliser?"
    echo "Jetbrains propose une édition payante et une édition gratuite"
    echo "1. Community (gratuit, choix par défaut)"
    echo "2. Ultimate (avec licence)"

    ask_for_edition_loop() {
        answer=-1
        printf "Faites votre choix: "
        read_entry

        case $answer in
            1|ic|c|community|'') EDITION=IC ;;
            2|iu|u|ultimate) EDITION=IU ;;
            *) echo "Choix incorrect"; ask_for_edition_loop ;;
        esac
    }

    ask_for_edition_loop
}

# Installe IntelliJ en décompressant un fichier .tar.gz et en ajoutant un fichier .desktop
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

# Désinstalle IntelliJ
remove () {
    echo "Supression fichiers IntelliJ"
    rm -rf $path/idea 2> /dev/null
    echo "Suppression .desktop"
    rm $desktop_files_path/idea.desktop 2> /dev/null
    rm $desktop_entry_auto_startup_path/install_intellij_idea.desktop 2> /dev/null
}

# Télécharge ou récupère le fichier .tar.gz contenant les fichiers de IntelliJ
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

# Installe IntelliJ quand c'est utile (installation ou mise à jour)
download_if_useful() {
    get_installed_version_number
    get_latest_version_number

	[[ $installed_version_number != -1 ]] && echo "Version actuelle de l'installation: ($installed_version_number)"

    if [[ $installed_version_number != $latest_version_number ]]
    then
    	if [[ $installed_version_number != -1 ]]
        then
            echo "Une nouvelle version d'IntelliJ est disponible! ($latest_version_number)"
            notify "Mise à jour de IntelliJ..."
        else
            notify "Installation de IntelliJ..."
        fi
        use_downloaded_tar_gz
    else
        no_need_to_update
    fi
}

# Télécharge le tar.gz depuis le site d'IntelliJ
use_downloaded_tar_gz () {
    mkdir -p $path

    if [ -f $script_dir/idea-*-download.tar.gz ]
    then
        use_already_downloaded_tar_gz
    else
        if [[ $KEEP_TAR_GZ_FILE == 1 ]]
        then
            get_latest_version_number
            tar_gz_path=$TAR_GZ_PATH/idea-$latest_version_number-download.tar.gz
        else
            tar_gz_path=$path/idea.tar.gz
        fi
        download_latest_version $tar_gz_path
        is_downloaded=true
    fi
}

use_already_downloaded_tar_gz() {
    current_tar_gz=$(ls $script_dir/idea-*-download.tar.gz | head -n 1)
    current_version=$(echo $current_tar_gz | cut -d - -f 2 )
    get_latest_version_number
    if [[ $current_version == $latest_version_number ]]
    then
        tar_gz_path=$current_tar_gz
        is_downloaded=false
    else
        rm $current_tar_gz
        tar_gz_path=$script_dir/idea-$latest_version_number-download.tar.gz
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
    echo "La dernière version d'IntelliJ IDEA est déjà installé!"
    echo "Vous pouvez utiliser le paramètre -f (--force) pour forcer la réinstallation"
    exit 0
}

# Récupère le fichier .tar.gz que l'utilisateur donne en paramètre
use_user_tar_gz () {
    tar_gz_path=$1
    check_path_validity
    is_downloaded=false
}

# Télécharge la dernière version de IntelliJ
# Si il n'y a pas internet, un message d'erreur s'affiche
download_latest_version () {
    echo "Téléchargement de la dernière version d'IntelliJ IDEA..."
    curl -L "https://download.jetbrains.com/product?code=I$EDITION&latest&distribution=linux" -o $tar_gz_path
    if [[ $? != 0 ]]
    then
        printf "Impossible de télécharger la dernière version d'IntelliJ IDEA, essayez de fournir un fichier .tar.gz\n'$script_name install <filename>.tar.gz'\n"
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

# Extrait le fichier .tar.gz avec le nom de dossier "idea"
extract_tar_gz () {
    mkdir -p $path
    echo "Extraction de IntelliJ IDEA à partir du fichier $tar_gz_path..."
    tar -xf $tar_gz_path -C $path

    if [[ $? != 0 ]]
    then
        echo "Erreur dans l'extraction du fichier"
        notify "Erreur dans l'extraction du fichier, consultez les logs"
        exit 4
    else
        echo "Extraction terminée!"
    fi

    rm -rf $path/idea 2> /dev/null
    mv $path/idea-$EDITION* $path/idea-$EDITION # Enlève le numéro de version à la fin du dossier
    notify "Installation terminée!"
}

# Ajoute le fichier .desktop pour pouvoir lancer l'application depuis le menu d'applications
add_desktop_entry () {
    mkdir -p $desktop_entry_path
    edition_name=$([[ $EDITION == 'IC' ]] && echo 'Community' || echo 'Ultimate')
    cat <<-EOF > $desktop_entry_path/idea.desktop
	[Desktop Entry]
	Version=1.0
	Type=Application
	Name=IntelliJ IDEA $edition_name Edition
	Comment=Develop with pleasure!
	Exec=$path/idea-$EDITION/bin/idea.sh %f
	Icon=$path/idea-$EDITION/bin/idea.svg
	Terminal=false
	StartupNotify=true
	StartupWMClass=jetbrains-idea-ce
	Categories=Development;IDE;Java;
	EOF
    echo "$desktop_content_launch"
    echo "Raccourci de l'application créé (vous devez peut-être redémarrer votre session pour voir le changement)"
}

# Ajoute le fichier .desktop pour lancer automatiquement le script à chaque démarrage de la session
run_script_on_startup () {
    mkdir -p $desktop_entry_auto_startup_path
    echo "$desktop_content_startup" > $desktop_entry_auto_startup_path/install_intellij_idea.desktop
    echo "Le script se lancera automatiquement au lancement de la session"
    echo "========="
    echo "IMPORTANT: Si vous changez l'emplacement du script, vous devrez relancer cette commande!"
    echo "========="
}

# Retire le fichier .desktop pour lancer automatiquement le script à chaque démarrage de la session
do_not_run_script_on_startup () {
    echo "Le script ne se lancera pas automatiquement"
    rm $desktop_entry_auto_startup_path/install_intellij_idea.desktop 2> /dev/null
    exit 0
}

# Supprime le fichier .tar.gz
delete_tar_gz () {
    rm $tar_gz_path
    echo "Fichier .tar.gz supprimé"
}

# Récupère le numéro de version d'IntelliJ qui est installée
get_installed_version_number () {
    installed_version_number=-1
    buildtxt_path=$path/idea-$EDITION/build.txt
    if [ -f $buildtxt_path ]
        then installed_version_number=$(cat $buildtxt_path | cut -d '-' -f 2)
    fi
}

# Récupère le dernier numéro de version d'IntelliJ
# Si il y a une erreur c'est égal à -1
get_latest_version_number () {
    latest_version_number=$(curl -s "https://data.services.jetbrains.com/products/releases?code=I$EDITION&latest=true&type=release" | grep -o '"build":"[^"]*' | grep -o '[^"]*$')
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
    echo "Outil d'installation de l'IDE IntelliJ sur les machines de l'IUT"
    echo
    echo "OBJECTS:"
    echo "  install                         Installe IntelliJ dans le dossier $path"
    echo "  remove                          Désinstalle IntelliJ (ne supprime pas les fichiers de configuration)"
    echo "  run_on_startup {true | false}   Lance automatiquement le script au démarrage d'une session"
    echo
    echo "OPTIONS:"
    echo "  -f                              Force la réinstallation de IntelliJ"
    echo "  -h                              Donne cette liste d'aide"
    echo "  -d                              Ne demande pas d'interaction à l'utilisateur"
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