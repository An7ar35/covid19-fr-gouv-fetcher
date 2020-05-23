#!/bin/bash
#************************************************#
#                   fetch.sh                     #
#              written by An7ar35                #
#                 27 March 2020                  #
#                                                #
#   Fetches the Covid-19 information page and    #
#   required forms from the French government    #
#   website and checks if there are any changes  #
#   on the text based files.                     #
#************************************************#


# Instruction: Run from the folder you want to store all the changes to
#              Use 'diff' to check the changes between versions

# Dependencies: 'date', 'wget', 'mapfile' (bash 4+), readarray (bash 4+), 'declare', 'sha256sum', 'awk', 'local' (bash 4+)

date=`date +'%Y-%m-%d'`
time=`date +'%H%M%S'`
info_page_address="https://www.gouvernement.fr/info-coronavirus"
document_domain_append="https://www.gouvernement.fr"
info_page_filename="info-coronavirus_${date}_${time}.html"
doc_attestation_base_filename="attestation-deplacement-fr_${date}_${time}"
doc_justificatif_base_filename="justificatif-professionnel-fr_${date}_${time}"
deconfinement_page_address="https://www.gouvernement.fr/info-coronavirus/strategie-de-deconfinement"
deconfinement_page_filename="strategie-de-deconfinement_${date}_${time}.html"
ressources_a_partager_page_address="https://www.gouvernement.fr/info-coronavirus/ressources-a-partager" #for the +100Km travels

#colours!
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # reset

#INFO BOX
INFO="${BLUE}[?]${NC}"
CHANGE="${GREEN}[+]${NC}"
NOCHANGE="${CYAN}[-]${NC}"
ERROR="${RED}[!]${NC}"

#-
# Removes file from disk
# @arg1 file path
#-
cleanup() {
    printf "${INFO} Cleaning up ${1} from disk...\n"
    rm ${1}
}

#-
# Downloads a set of file links
# @arg1 collection of domainless paths
# @arg2 base filename to use for naming downloaded files
# @return 
#-
download() {
    local -n paths=$1 #passed by reference
    error="0"
    
    for i in "${paths[@]}"; do
        if [[ ! -f "$i" ]]; then
            wget_retval=""
            remote="${document_domain_append}${i}"
            printf "${INFO} Téléchargement: ${remote}\n"
            
            if [[ "${i: -4}" == ".txt" ]]; then
                wget -qO "${2}.txt" ${remote}
                wget_retval=$?
            elif [[ "${i: -4}" == ".pdf" ]]; then
                wget -qO "${2}.pdf.gz" ${remote}
                wget_retval=$?
            elif [[ "${i: -4}" == "docx" ]]; then
                wget -qO "${2}.docx.gz" ${remote}
                wget_retval=$?
            else
                printf "${ERROR} Extention non roconnue: ${i: -4}\n"
            fi          
            
            if [[ "$wget_retval" == -1 ]]; then
                printf "${ERROR} Téléchargement a échoué: ${remote}\n"
                error="-1" #ERROR: failed page fetching
            fi
        fi
    done
    
    return ${error}
}

#-
# Hash the content of the last known version of a type of file
# @arg1   File search parameter to pass to 'ls'
# @arg2   Last known hash
# @return '1' if found, 
#         '0' if not found
#-
hashLastKnownVersion() {
    local -n last_hash=$2 #passed by reference
    files=($(ls ${1} 2> /dev/null))
    
    if (( ${?} > 0 )); then
        return 0 #Not found
    fi
    
    if [[ "${#files[@]}" -ne 0 ]]; then
        #echo "DEBUG: Found ${#files[@]} files"
        #echo "DEBUG: ${files[@]}"
        
        readarray -t sorted_files < <(printf '%s\0' "${files[@]}" | sort -rz | xargs -0n1)
        last_hash=`cat ${sorted_files[0]} | sha256sum | awk {'print $1'}`
        
        #echo "DEBUG: Most recent file (${sorted_files[0]}) hash: ${last_hash}"
        
        return 1
    fi
    
    return 0
}

#-
# Fetches the information page
# @arg1   (optional) Hash of the last known version of the html file on disk (empty=not found)
# @return '-1' if fetching failed, 
#         ' 0' if no changes detected, 
#         ' 1' if first time download
#         ' 2' if changes have been detected
#-
fetchInfoPage() {
    #download the new HTML page
    printf "${INFO} Téléchargement de la page d'info: ${info_page_address}\n"
    wget -qO ${info_page_filename} ${info_page_address}
    wget_retval=$?

    if [[ "$wget_retval" == -1 ]]; then
        printf "${ERROR} Téléchargement de la page d'info a échoué.\n"
        return -1 #ERROR: failed page fetching
    fi

    #hash new content and compare it to previous version
    if [[ -n "$1" ]]; then #previous hash passed as arg1
        new_hash=`cat ${info_page_filename} | sha256sum | awk {'print $1'}`
        if [[ "$1" == "$new_hash" ]]; then
            printf "${NOCHANGE} Pas de changement de la page d'information.\n"
            return 0; #no changes detected
        else
            printf "${CHANGE} La page d'information a changer depuis le dernier telechargement.\n"
            return 2; #changes detected
        fi
    else
        printf "${CHANGE} Premièr téléchargement de la page d'info.\n"
        return 1; #no precious version so no changes to be detected
    fi
}

#-
# Fetches the "Attestation de deplacement" documents in the various formats (pdf/docx/txt)
# @arg1   (optional) Hash of the last known version of the txt file on disk (empty=not found)
# @return '-1' if fetching failed, 
#         ' 0' if no changes detected, 
#         ' 1' if first time download
#         ' 2' if changes have been detected
#-
fetchAttestationDocs() {    
    #Parse info page HTML to find the file links
    declare -A fichiers_attestation
    rx_attestation="(?:\/sites\/default\/files\/cfiles\/attestation-deplacement-fr-)[\d]{8}\.(pdf|docx|txt)"
    
    mapfile -t paths < <( cat ${info_page_filename} | grep -oP ${rx_attestation} )

    for i in "${paths[@]}"; do
        hash=`echo $i | sha256sum`
        fichiers_attestation[$hash]=$i
    done

    for i in "${fichiers_attestation[@]}"; do
        if [[ "${i: -4}" == ".txt" ]]; then
            attestation_txt_path=$i
        fi
    done
    
    if [[ "$attestation_txt_path" == "" ]]; then
        printf "${ERROR} Lien de la version 'txt' de l'attestation n'a pas pu être parser.\n"
        return -1 #ERROR: failed link parsing from HTML
    fi

    #download the txt document
    remote_txt="${document_domain_append}${attestation_txt_path}"
    local_txt="${doc_attestation_base_filename}.txt"
    
    printf "${INFO} Téléchargement de l'attestation de deplacement: ${remote_txt}\n"
    wget -qO ${local_txt} ${remote_txt}
    wget_retval=$?

    if [[ "$wget_retval" == -1 ]]; then
        printf "${ERROR} Téléchargement de l'attestation de deplacement en format 'txt' a échoué.\n"
        return -1 #ERROR: failed document fetching
    fi    
    
    #hash new content and compare it to previous version
    if [[ -n "$1" ]]; then #previous hash passed as arg1
        new_hash=`cat ${local_txt} | sha256sum | awk {'print $1'}`
        
        if [[ "$1" == "$new_hash" ]]; then
            printf "${NOCHANGE} Pas de changement de l'attestation de deplacement (txt).\n"
            cleanup $local_txt
            return 0; #no changes detected
        else
            printf "${CHANGE} L'attestation de deplacement a changer depuis le dernier telechargement.\n"
            download fichiers_attestation ${doc_attestation_base_filename}
            return 2; #changes detected
        fi
    else
        printf "${CHANGE} Premièr téléchargement de l'attestation de deplacement.\n"
        download fichiers_attestation ${doc_attestation_base_filename}
        return 1; #no precious version so no changes to be detected
    fi
}

#-
# Fetches the "Justificatif de deplacement professionnel" documents in the various formats (pdf/docx/txt)
# @arg1 (optional) Hash of the last known version of the txt file on disk (empty=not found)
# @return '-1' if fetching failed, 
#         ' 0' if no changes detected, 
#         ' 1' if first time download
#         ' 2' if changes have been detected
#-
fetchJustificatifDocs() {   
    declare -A fichiers_justificatif
    rx_justificatif="(?:\/sites\/default\/files\/cfiles\/justificatif-deplacement-professionnel-fr_)[\d]{8}\.(pdf|docx|txt)"
    
    mapfile -t paths < <( cat ${info_page_filename} | grep -oP ${rx_justificatif} )

    for i in "${paths[@]}"; do
        hash=`echo $i | sha256sum`
        fichiers_justificatif[$hash]=$i
    done
    
    justificatif_txt_path=""
    
    for i in "${fichiers_justificatif[@]}"; do
        if [[ "${i: -4}" == ".txt" ]]; then
            justificatif_txt_path=$i
        fi
    done
    
    if [[ "$justificatif_txt_path" == "" ]]; then
        printf "${ERROR} Lien de la version 'txt' du justificatif n'a pas pus être parser.\n"
    fi
    
    #download the txt document
    remote_txt="${document_domain_append}${justificatif_txt_path}"
    local_txt="${doc_justificatif_base_filename}.txt"
    
    printf "${INFO} Téléchargement du justificatif de deplacement professionnel: ${remote_txt}\n"
    wget -qO ${local_txt} ${remote_txt}
    wget_retval=$?

    if [[ "$wget_retval" == -1 ]]; then
        printf "${ERROR} Téléchargement du justificatif de deplacement professionnel format 'txt' a échoué.\n"
        return -1 #ERROR: failed document fetching
    fi    
    
    #hash new content and compare it to previous version
    if [[ -n "$1" ]]; then #previous hash passed as arg1
        new_hash=`cat ${local_txt} | sha256sum | awk {'print $1'}`
        
        if [[ "$1" == "$new_hash" ]]; then
            printf "${NOCHANGE} Pas de changement du justificatif de deplacement professionnel (txt).\n"
            cleanup $local_txt
            return 0; #no changes detected
        else
            printf "${CHANGE} Le justificatif de deplacement professionnel a changer depuis le dernier telechargement.\n"
            download fichiers_justificatif ${doc_justificatif_base_filename}
            return 2; #changes detected
        fi
    else
        printf "${CHANGE} Premièr téléchargement du justificatif de deplacement professionnel.\n"
        download fichiers_justificatif ${doc_justificatif_base_filename}
        return 1; #no previous version so no changes to be detected
    fi
}

#-
# Fetches the "Attestation pour un déplacement dérogatoire de la France métropolitaine vers l'Outre-mer" PDF document
# @return '-1' if fetching failed, 
#         ' 0' if no changes detected, 
#         ' 1' if first time download
#         ' 2' if changes have been detected
#-
fetchTravelAttestation1() {
    filename="attestation-om-depuis-la-metropole.pdf"
    old_hash=""
    new_hash=""
    rx="(?:https:\/\/www\.interieur\.gouv\.fr\/content\/download\/)([\d]+\/[\d]+\/)file\/([\d-]*Attestation-om-depuis-la-metropole)\.(?=pdf)"
    
    if [[ -f "$filename" ]]; then
        old_hash=`sha256sum "$filename" | awk {'print $1'}`  
    fi

    remote=`cat ${info_page_filename} | grep -oP ${rx}`
    
    printf "${INFO} Téléchargement de l'attestation pour un déplacement dérogatoire de la France métropolitaine vers l'Outre-mer: ${filename}\n"
    wget -qO ${filename} ${remote}
    wget_retval=$?
    
    if [[ "$wget_retval" == -1 ]]; then
        printf "${ERROR} Téléchargement de l'attestation pour un déplacement dérogatoire de la France métropolitaine vers l'Outre-mer en format 'pdf' a échoué.\n"
        return -1 #ERROR: failed document fetching
    fi
    
    if [[ ! -n "$old_hash" ]]; then
        printf "${CHANGE} Premièr téléchargement de attestation pour un déplacement dérogatoire de la France métropolitaine vers l'Outre-mer.\n"
        return 1; #first download
    fi
    
    new_hash=`sha256sum "$filename" | awk {'print $1'}`
    
    if [[ "$old_hash" = "$new_hash" ]]; then
        printf "${NOCHANGE} Pas de changement de l'attestation pour un déplacement dérogatoire de la France métropolitaine vers l'Outre-mer.\n"
        return 0; #no changes detected
    else
        printf "${CHANGE} L'attestation pour un déplacement dérogatoire de la France métropolitaine vers l'Outre-mer a changer depuis le dernier telechargement.\n"
        return 2; #changes detected
    fi    
}

#-
# Fetches the "Attestation pour un voyage international depuis l'étranger vers la France métropolitaine" PDF document
# @return '-1' if fetching failed, 
#         ' 0' if no changes detected, 
#         ' 1' if first time download
#         ' 2' if changes have been detected
#-
fetchTravelAttestation2() {    
    filename="attestation-etranger-metropole-fr.pdf"
    old_hash=""
    new_hash=""
    rx="(?:https:\/\/www\.interieur\.gouv\.fr\/content\/download\/)([\d]+\/[\d]+\/)file\/([\d-]*Attestation-etranger-metropole-FR)\.(?=pdf)"
    
    if [[ -f "$filename" ]]; then
        old_hash=`sha256sum "$filename" | awk {'print $1'}`  
    fi

    remote=`cat ${info_page_filename} | grep -oP ${rx}`
    
    printf "${INFO} Téléchargement de l'attestation pour un voyage international depuis l'étranger vers la France métropolitaine: ${filename}\n"
    wget -qO ${filename} ${remote}
    wget_retval=$?
    
    if [[ "$wget_retval" == -1 ]]; then
        printf "Téléchargement de l'attestation pour un voyage international depuis l'étranger vers la France métropolitaine 'pdf' a échoué.\n"
        return -1 #ERROR: failed document fetching
    fi
    
    if [[ ! -n "$old_hash" ]]; then
        printf "${CHANGE} Premièr téléchargement de l'attestation pour un voyage international depuis l'étranger vers la France métropolitaine.\n"
        return 1; #first download
    fi
    
    new_hash=`sha256sum "$filename" | awk {'print $1'}`
    
    if [[ "$old_hash" = "$new_hash" ]]; then
        printf "${NOCHANGE} Pas de changement de l'attestation pour un déplacement dérogatoire de la France métropolitaine vers l'Outre-mer.\n"
        return 0; #no changes detected
    else
        printf "${CHANGE} L'attestation pour un voyage international depuis l'étranger vers la France métropolitaine a changer depuis le dernier telechargement.\n"
        return 2; #changes detected
    fi    
}

#-
# Fetches the "Attestation pour un voyage international depuis l'étranger vers une collectivité d'Outre-mer" PDF document
# @return '-1' if fetching failed, 
#         ' 0' if no changes detected, 
#         ' 1' if first time download
#         ' 2' if changes have been detected
#-
fetchTravelAttestation3() {
    filename="attestation-outre-mer-depuis-l-etranger.pdf"
    old_hash=""
    new_hash=""
    rx="(?:https:\/\/www\.interieur\.gouv\.fr\/content\/download\/)([\d]+\/[\d]+\/)file\/([\d-]*Attestation-outre-mer-depuis-l-etranger)\.(?=pdf)"
    
    if [[ -f "$filename" ]]; then
        old_hash=`sha256sum "$filename" | awk {'print $1'}`  
    fi

    remote=`cat ${info_page_filename} | grep -oP ${rx}`
    
    printf "${INFO} Téléchargement de l'attestation pour un voyage international depuis l'étranger vers une collectivité d'Outre-mer: ${filename}\n"
    wget -qO ${filename} ${remote}
    wget_retval=$?
    
    if [[ "$wget_retval" == -1 ]]; then
        printf "${ERROR} Téléchargement de l'attestation pour un voyage international depuis l'étranger vers une collectivité d'Outre-mer 'pdf' a échoué.\n"
        return -1 #ERROR: failed document fetching
    fi
    
    if [[ ! -n "$old_hash" ]]; then
        printf "${CHANGE} Premièr téléchargement de l'attestation pour un voyage international depuis l'étranger vers une collectivité d'Outre-mer.\n"
        return 1; #first download
    fi
    
    new_hash=`sha256sum "$filename" | awk {'print $1'}`
    
    if [[ "$old_hash" = "$new_hash" ]]; then
        printf "${NOCHANGE} Pas de changement de l'attestation pour un voyage international depuis l'étranger vers une collectivité d'Outre-mer.\n"
        return 0; #no changes detected
    else
        printf "${CHANGE} L'attestation pour un voyage international depuis l'étranger vers une collectivité d'Outre-mer a changer depuis le dernier telechargement.\n"
        return 2; #changes detected
    fi    
}

#-
# Fetches the 'Strategie de Deconfinement' page
# @arg1   (optional) Hash of the last known version of the html file on disk (empty=not found)
# @return '-1' if fetching failed, 
#         ' 0' if no changes detected, 
#         ' 1' if first time download
#         ' 2' if changes have been detected
#-
fetchDeconfinementPage() {
    #download the new HTML page
    printf "${INFO} Téléchargement de la page de strategie de deconfinement: ${deconfinement_page_address}\n"
    wget -qO ${deconfinement_page_filename} ${deconfinement_page_address}
    wget_retval=$?

    if [[ "$wget_retval" == -1 ]]; then
        printf "${ERROR} Téléchargement de la page de strategie de deconfinement a échoué.\n"
        return -1 #ERROR: failed page fetching
    fi

    #hash new content and compare it to previous version
    if [[ -n "$1" ]]; then #previous hash passed as arg1
        new_hash=`cat ${deconfinement_page_filename} | sha256sum | awk {'print $1'}`
        if [[ "$1" == "$new_hash" ]]; then
            printf "${NOCHANGE} Pas de changement de la page de strategie de deconfinement.\n"
            return 0; #no changes detected
        else
            printf "${CHANGE} La page de strategie de deconfinement a changer depuis le dernier telechargement.\n"
            return 2; #changes detected
        fi
    else
        printf "${CHANGE} Premièr téléchargement de la page de strategie de deconfinement.\n"
        return 1; #no precious version so no changes to be detected
    fi
}

#-
# Fetches the 'Déclaration de déplacement +100Km' PDF document
# @arg1   (optional) Hash of the last known version of the html file on disk (empty=not found)
# @return '-1' if fetching failed, 
#         ' 0' if no changes detected, 
#         ' 1' if first time download
#         ' 2' if changes have been detected
#-
fetchOver100KmTravelForm() {
    filename="declaration-deplacement-fr-pdf.pdf.gz"
    old_hash=""
    new_hash=""
    rx="(?:https:\/\/www\.gouvernement\.fr\/sites\/default\/files\/)([\d-]*declaration-de-deplacement-fr.pdf)"
    
    if [[ -f "$filename" ]]; then
        old_hash=`sha256sum "$filename" | awk {'print $1'}`  
    fi

    src_page=$(wget -qO- ${ressources_a_partager_page_address})
    if [[ "$?" == -1 ]]; then
        printf "${ERROR} Téléchargement de la page de resources a partager a échoué (pour télécharger la déclaration de déplacement +100Km).\n"
        return -1 #ERROR: source page for the form failed to download
    fi
    
    remote=`echo ${src_page} | grep -oP ${rx}`
    
    printf "${INFO} Téléchargement de la déclaration de déplacement +100Km: ${filename}\n"
    wget -qO ${filename} ${remote}
    wget_retval=$?
    
    if [[ "$wget_retval" == -1 ]]; then
        printf "${ERROR} Téléchargement de la déclaration de déplacement +100Km 'pdf' a échoué.\n"
        return -1 #ERROR: failed document fetching
    fi
    
    if [[ ! -n "$old_hash" ]]; then
        printf "${CHANGE} Premièr téléchargement de la déclaration de déplacement +100Km.\n"
        return 1; #first download
    fi
    
    new_hash=`sha256sum "$filename" | awk {'print $1'}`
    
    if [[ "$old_hash" = "$new_hash" ]]; then
        printf "${NOCHANGE} Pas de changement de la déclaration de déplacement +100Km.\n"
        return 0; #no changes detected
    else
        printf "${CHANGE} La déclaration de déplacement +100Km a changer depuis le dernier telechargement.\n"
        return 2; #changes detected
    fi    
}

# RUN SECTION OF THE SCRIPT! #
most_recent_info_page_hash=""
hashLastKnownVersion "info-coronavirus*.html" most_recent_info_page_hash
fetchInfoPage $most_recent_info_page_hash
fetchInfoPage_retval=$?

most_recent_deconfinement_page_hash=""
hashLastKnownVersion "strategie-de-deconfinement*.html" most_recent_deconfinement_page_hash
fetchDeconfinementPage $most_recent_deconfinement_page_hash
fetchDeconfinementPage_retval=$?

#most_recent_attestation_hash=""
#hashLastKnownVersion "attestation-deplacement-fr*.txt" most_recent_attestation_hash
#fetchAttestationDocs $most_recent_attestation_hash
#fetchAttestationDocs_retval=$?

#most_recent_justificatif_hash=""
#hashLastKnownVersion "justificatif-professionnel-fr*.txt" most_recent_justificatif_hash
#fetchJustificatifDocs $most_recent_justificatif_hash
#fetchJustificatifDocs_retval=$?

#fetchTravelAttestation1
#fetchTravelAttestation1_retval=$?
#fetchTravelAttestation2
#fetchTravelAttestation2_retval=$?
#fetchTravelAttestation3
#fetchTravelAttestation3_retval=$?
fetchOver100KmTravelForm
fetchOver100KmTravelForm_retval=$?

# CLEANUP
if [[ "$fetchInfoPage_retval" == 0 ]]; then
    cleanup $info_page_filename
fi

if [[ "$fetchDeconfinementPage_retval" == 0 ]]; then
    cleanup $deconfinement_page_filename
fi







