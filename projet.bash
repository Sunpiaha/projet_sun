#!/bin/bash


echo "entrer le nom du premier répertoire: "
read rA
echo "entrer le nom du deuxième répertoire: "
read rB
echo "entrer le nom du fichier à synchroniser: "
read p

# Vérifier le nombre de valeurs
while [[ "$rA" == *" "* || "$rB" == *" "* || "$p" == *" "* || "$rA" == "" || "$rB" == "" || "$p" == "" ]]; do # si espace ou aucune saisie dans la saisie alors plus d’une valeur
    echo "Erreur : Vous devez entrer exactement 1  valeur pour chacune."
    echo "veuillez recommencer la saisie:"
    read rA
    read rB
    read p
done

while true; do
   # Compter le nombre d'occurrences de chaque répertoire
    count_rA=$(find / -type d -name "$rA" 2>/dev/null | wc -l)
    count_rB=$(find / -type d -name "$rB" 2>/dev/null | wc -l)

    # Vérifier que les répertoires sont les seuls présents
    if [ $count_rA -eq 1 ] && [ $count_rB -eq 1 ]; then
        echo "Les valeurs de repertoires saisies sont valides. Les deux répertoires sont les seuls dans toute l'arborescence."
        break
    elif [ $count_rA != 1 ]; then
        echo "veuillez recommencer la saisie du premier repertoire"
        read rA
    elif [ $count_rB != 1 ]; then
        echo "veuillez recommencer la saisie du deuxieme repertoire"
        read rB
    else
        echo "veuillez recommencer la saisie des 2 répertoires."
        read rA
        read rB
    fi
done

cheminA=$(find / -type d -name "$rA" 2>/dev/null)
cheminB=$(find / -type d -name "$rB" 2>/dev/null)

fichier_A="$cheminA/$p"
fichier_B="$cheminB/$p"


# Vérifiez si le fichier p existe dans chaque arborescence
if [ -e "$fichier_A" ] && [ -e "$fichier_B" ]; then
	echo "Le fichier existe dans les 2 répertoires spécifiés"
else
	echo "Le fichier n'existe pas dans les deux arborescence"
	exit
fi

recuperer_meta_fichier() {
    local chemin=$1
    local metadonnee=$(ls -l "$1" | awk '{print $1 " " $5 " " $6 " " $7}')
    echo "$metadonnee"
}
recuperer_meta_journal() {
    local cheminA=$1
    local cheminB=$2
    local metadonnee=$(grep "^$1 $2\|^$2 $1" journal | awk '{print $7 " " $8 " " $9 " " $10}')
    echo "$metadonnee"
}
sync_simple() {
    local p_A=$1
    local p_B=$2
    echo "processus de synchronisation de $p_A et $p_B en cours"
    meta_p_A="$(recuperer_meta_fichier "$p_A")" #on récupere les métadonnées de p_A avec la fonction
    meta_p_B="$(recuperer_meta_fichier "$p_B")" #on récupere les métadonnées de p_B avec la fonction
    meta_journal="$(recuperer_meta_journal "$p_A" "$p_B")"
    
    #parcourir les arbres A et B en parallèle
    # Vérifier si l'un des fichiers est un lien symbolique
    if [ -L "$p_A" ] || [ -L "$p_B" ]; then
        echo "Conflit: $p_A ou $p_B est un lien symbolique."
    #cela correspond au cas repertoire fichier ordinaire
    elif [ -d "$p_A" ] && [ -f "$p_B" ]; then
        echo "conflit: $p_A est un repertoire dans un arbre et $p_B est un fichier dans l'autre"
    elif [ -f "$p_A" ] && [ -d "$p_B" ]; then
        echo "conflit: $p_B est un repertoire dans un arbre et $p_A est un fichier dans l'autre"
    #cela correspond au cas repertoire repertoire
    elif [ -d "$p_A" ] && [ -d "$p_B" ]; then
    #descendre recursivement dans ce cas
    #On parcourt récursivement les fichiers et répertoires à l'intérieur des répertoires
    #Synchroniser les fichiers de $p_A vers $p_B
        for element in "$p_A"/*; do
            element_relatif="${element/$p_A/$p_B}"
            if [ -e "$element_relatif" ]; then
                # Le fichier existe dans les deux répertoires
                sync_simple "$element" "$element_relatif"
                gestion_conflit "$element" "$element_relatif"
		echo "fin sync_simple"
            else
                # Le fichier existe uniquement dans $p_A, le copier dans $p_B
                cp -r "$element" "$element_relatif"
                echo "Copie de $element dans le repertoire $p_B."
            fi
        done
        # Synchroniser les fichiers de $p_B vers $p_A
        for element in "$p_B"/*; do
            element_relatif="${element/$p_B/$p_A}"
            if [ ! -e "$element_relatif" ]; then
                # Le fichier existe uniquement dans $p_B, le copier dans $p_A
                cp -r "$element" "$element_relatif"
                echo "Copie de $element dans le repertoire $p_A."
            fi
        done
	echo "processus de synchronisation de repertoire reussie"
    #cela correspond au cas fichier ordinaire fichier ordinaire
    elif [ -f "$p_A" ] && [ -f "$p_B" ]; then
        local type="fichier ordinaire"
        #verifier si les metadonnées des deux fichiers sont identiques
        if [ "$meta_p_A" = "$meta_p_B" ]; then
            echo " synchronisation reussie cas ideal."
            #verifier s'il existe une entree pour ces deux fichiers
            if grep "^$p_A $p_B\|^$p_B $p_A" journal > /dev/null 2>&1; then
                sed -i "s#^$p_A $p_B\|^$p_B $p_A.*#''#" journal
                echo "$p_A $p_B $type $(date '+%m %d') $meta_p_A" >> journal
            #ajout d'une entrée si entrée absente
            else
                echo "$p_A $p_B $type $(date '+%m %d') $meta_p_A" >> journal
            fi
        #cas ou les metadonnées des deux fichiers ne sont pas identiques
        else
            #vérifier s'il existe une entree pour ces deux fichiers
            if grep "^$p_A $p_B\|^$p_B $p_A" journal > /dev/null 2>&1; then
                #si oui comparer ces metadonnées avec celles du fichier journal
                if [ "$meta_p_A" = "$meta_journal" ] && [ "$meta_p_B" != "$meta_journal" ]; then #cas ou l'une des metadonnées est identique avec celles du fichier journal
                    cp "$p_B" "$p_A"
                    meta_journal="$meta_p_B"
                    meta_p_A=$(ls -l "$p_A" | awk '{print $1 " " $5 " " $6 " " $7}')
                    sed -i "s#\(^$p_A $p_B\|^$p_B $p_A\).*#\1 $type $(date '+%m %d') $meta_journal#" journal
                    echo "synchronisation 1 reussie"
                elif [ "$meta_p_A" != "$meta_journal" ] && [ "$meta_p_B" = "$meta_journal" ]; then #cas ou l'une des metadonnées est identique avec celles du fichier jourrnal
                    cp "$p_A" "$p_B"
                    meta_journal="$meta_p_A"
                    meta_p_B=$(ls -l "$p_B" | awk '{print $1 " " $5 " " $6 " " $7}')
                    sed -i "s#\(^$p_A $p_B\|^$p_B $p_A\).*#\1 $type $(date '+%m %d') $meta_journal#" journal
                    echo "synchronisation 2 reussie "
                else
                    echo "conflit 2"
                fi
            else
                echo "conflit 3"
            fi
        fi
    fi
}
sync_contenu() {
    local p_A=$1
    local p_B=$2

    echo "processus de synchronisation de $p_A et $p_B en cours"
    meta_p_A="$(recuperer_meta_fichier "$p_A")"
    meta_p_B="$(recuperer_meta_fichier "$p_B")"
    meta_journal="$(recuperer_meta_journal "$p_A" "$p_B")"
    
    if [ -f "$p_A" ] && [ -f "$p_B" ]; then
	local type="fichier ordinaire"
        if cmp "$p_A" "$p_B" > /dev/null 2>&1; then
            echo "conflit fallacieux"
            if [ "$meta_p_A" = "$meta_p_B" ]; then
                echo "synchronisation reussie cas ideal"
                #verifier s'il existe une entree pour ces deux fichiers
                if grep "^$p_A $p_B\|^$p_B $p_A" journal > /dev/null 2>&1; then
                    sed -i "s#^$p_A $p_B\|^$p_B $p_A.*#''#" journal
                    echo "$p_A $p_B $type $(date '+%m %d') $meta_p_A" >> journal
                    exit
                #ajout d'une entrée si entrée absente
                else
                    echo "$p_A $p_B $type $(date '+%m %d') $meta_p_A">>journal 
                fi
            #cas ou les metadonnées des deux fichiers ne sont pas identiques
            else
                #vérifier s'il existe une entree pour ces deux fichiers
                if grep "^$p_A $p_B\|^$p_B $p_A" journal > /dev/null 2>&1; then
                    #si oui comparer ces metadonnées avec celles du fichier journal
                    if [ "$meta_p_A" = "$meta_journal" ] && [ "$meta_p_B" != "$meta_journal" ]; then #cas ou l'une des metadonnées est identique avec celles du fichier journal
                        cp "$p_B" "$p_A"
                        meta_journal="$meta_p_B"
                        sed -i "s#\(^$p_A $p_B\|^$p_B $p_A\).*#\1 $type $(date '+%m %d') $meta_journal#" journal
                        echo "synchronisation 1 reussie"
                    elif [ "$meta_p_A" != "$meta_journal" ] && [ "$meta_p_B" = "$meta_journal" ]; then #cas ou l'une des metadonnées est identique avec celles du fichier journal
                        cp "$p_A" "$p_B"
                        meta_journal="$meta_p_A"
                        sed -i "s#\(^$p_A $p_B\|^$p_B $p_A\).*#\1 $type $(date '+%m %d') $meta_journal#" journal
                        echo "synchronisation 2 reussie "
                    else
                        echo "conflit: $p_A et $p_B ont des metadonnées differentes."
                    fi
                else
                    echo "conflit 3"
                fi
            fi
        else 
            if [ "$meta_p_A" = "$meta_p_B" ]; then 
                echo "conflit de contenu uniquement"
                diff "$p_A" "$p_B" | grep '^>' | echo "il y a en tout $(wc -l) differences entre les deux fichiers"
                echo " les differences sont : "
                diff "$p_A" "$p_B"
            else
                if grep "^$p_A $p_B\|^$p_B $p_A" journal > /dev/null 2>&1; then
                    if [ "$meta_p_A" = "$meta_journal" ] && [ "$meta_p_B" != "$meta_journal" ] || [ "$meta_p_A" != "$meta_journal" ] && [ "$meta_p_B" = "$meta_journal" ]; then
                        echo "conflit de contenu et de metadonnées 1"
                    else
                	echo "conflit de contenu et de metadonnées.2"
                    fi
                else
                    echo "conflit"
                fi
            fi
        fi
    fi
}

interface_utilisateur() {
    local p_A=$1
    local p_B=$2

    if [ -f "$p_A" ] && [ -f "$p_B" ] && [ ! -L "$p_A" ] && [ ! -L "$p_B" ]; then
        # Demander à l'utilisateur de choisir le mode de synchronisation
        echo "Veuillez choisir le mode de synchronisation :"
        echo "1. Synchronisation simple"
        echo "2. Synchronisation avec comparaison du contenu"
        read mode_synchro

        case $mode_synchro in
            1) sync_simple "$fichier_A" "$fichier_B";;
            2) sync_contenu "$fichier_A" "$fichier_B";; 
            *) echo "Choix invalide. Quitter.";;
        esac
    else
	echo "le processus de synchronisation simple va se lancer automatiquement"
	sync_simple "$fichier_A" "$fichier_B"
    fi
}
gestion_conflit() {
    local p_A=$1
    local p_B=$2
    if [ -L "$p_A" ] || [ -L "$p_B" ]; then
        # Gestion des liens symboliques : copier le lien symbolique
        local lien_destination_A=$(ls -l "$p_A" | awk '{print $NF}')
        local lien_destination_B=$(ls -l "$p_B" | awk '{print $NF}')

        if [ "$lien_destination_A" != "$lien_destination_B" ]; then
            echo "Différences dans les destinations des liens symboliques :"
	    #creation de tubes permettent de rediriger la sortie de chaque echo vers diff comme s'il s'agissait de fichiers
            diff <(echo "$lien_destination_A") <(echo "$lien_destination_B")

            # Demander à l'utilisateur de choisir la destination
            echo "saisissez A si vous souhaitez sauvegarder la destination de $p_A et B dans le cas contraire"
	    read choix1
            case $choix1 in
                A|a)
		    rm "$p_B"
                    ln -s "$lien_destination_A" "$p_B"
                    echo "Synchronisation réussie : Copie du lien de $p_A vers $p_B."
                    ;;
                B|b)
		    rm "$p_A"
                    ln -s "$lien_destination_B" "$p_A"
                    echo "Synchronisation réussie : Copie du lien de $p_B vers $p_A."
                    ;;
                *)
                    echo "Choix non valide. Aucune action effectuée."
                    ;;
            esac
        else
            echo "Synchronisation réussie pour les liens symboliques $p_A et $p_B."
        fi
    elif [ -f "$p_A" ] && [ -d "$p_B" ]; then
        echo "Voulez-vous renommer ou deplacer le répertoire ou le fichier pour résoudre le conflit ?"
        echo "1. Renommer le fichier $p_A"
        echo "2. Renommer le répertoire $p_B"
        echo "3. déplacer le fichier $p_A"
        echo "4. déplacer le répertoire $p_B"
        read option
        case $option in
            1)
                echo "entrer le nouveau nom que vous souhaitez attribuer au fichier"
                read nom
	        while [ -e "$cheminA/$nom" ]; do
                    echo "Un fichier avec le nom $nom existe déjà. Veuillez choisir un autre nom :"
                    read nom
                done
                mv "$p_A" "$cheminA/$nom"
                echo "vous venez de renommer votre fichier en $nom"
                ;;
            2)
                echo "entrer le nouveau nom que vous souhaitez attribuer au repertoire"
                read nom
                while [ -e "$cheminB/$nom" ]; do
                    echo "Un répertoire avec le nom $nom existe déjà. Veuillez choisir un autre nom :"
                    read nom
                done
                mv "$p_B" "$cheminB/$nom"
                echo "vous venez de renommer votre repertoire en $nom"
                ;;
            3)
		while true; do
                    # Demander à l'utilisateur de saisir un répertoire
                    echo  "Veuillez saisir un répertoire où déplacer le fichier: "
                    read repertoire
                    chemin_rep=$(find / -type d -name "$repertoire" 2>/dev/null)
                    # Vérifier si le répertoire existe et est unique
                    if [ -n "$chemin_rep" ] &&[ "$(echo "$chemin_rep" | wc -l)" -eq 1 ]; then
                    # Vérifier si le répertoire ne contient pas un fichier de nom $p
                        if [ ! -e "$chemin_rep/$p" ]; then
                            echo "Répertoire valide."
                            mv "$p_A" "$chemin_rep"
                            echo "Vous venez de déplacer votre fichier vers le répertoire spécifié : $repertoire"
                            break
                        else
                            echo "Le répertoire contient un fichier avec le nom $p. Veuillez réessayer."
                        fi
                    else
                        echo "Répertoire invalide. Veuillez réessayer."
                    fi 
                done
                ;;
            4)
                while true; do
                    # Demander à l'utilisateur de saisir un répertoire
                    echo  "Veuillez saisir un répertoire où deplacer le repertoire: "
	            read repertoire
	            chemin_rep=$(find / -type d -name "$repertoire" 2>/dev/null)
                    # Vérifier si le répertoire existe et est unique
	            if [ -n "$chemin_rep" ] &&[ "$(echo "$chemin_rep" | wc -l)" -eq 1 ]; then
                    # Vérifier si le répertoire ne contient pas un fichier de nom $p
                        if [ ! -e "$chemin_rep/$p" ]; then
                            echo "Répertoire valide."
                            mv "$p_B" "$chemin_rep"
        	            echo "Vous venez de déplacer votre répertoire vers le répertoire spécifié : $repertoire"
                            break
                        else
                            echo "Le répertoire contient un fichier avec le nom $p. Veuillez réessayer."
                        fi
                    else
                        echo "Répertoire invalide. Veuillez réessayer."
                    fi 
                done
                ;;
            *)
                echo "Choix invalide. Aucune action effectuée.";;
        esac
    elif [ -d "$p_A" ] && [ -f "$p_B" ]; then
        echo "Voulez-vous renommer ou deplacer le répertoire ou le fichier pour résoudre le conflit ?"
        echo "1. Renommer le fichier $p_B"
        echo "2. Renommer le répertoire $p_A"
        echo "3. déplacer le fichier $p_B"
        echo "4. déplacer le répertoire $p_A"
        read option
        case $option in
            1)
                echo "entrer le nouveau nom que vous souhaitez attribuer au fichier"
                read nom
                while [ -e "$cheminA/$nom" ]; do
                    echo "Un fichier avec le nom $nom existe déjà. Veuillez choisir un autre nom :"
                    read nom
                done
                mv "$p_B" "$cheminB/$nom"
                echo "vous venez de renommer votre fichier en $nom"
                ;;
            2)
                echo "entrer le nouveau nom que vous souhaitez attribuer au repertoire"
                read nom
		while [ -e "$cheminB/$nom" ]; do
                    echo "Un répertoire avec le nom $nom existe déjà. Veuillez choisir un autre nom :"
                    read nom
                done
                mv "$p_A" "$cheminA/$nom"
                echo "vous venez de renommer votre repertoire en $nom"
                ;;
            3)
		while true; do
                    # Demander à l'utilisateur de saisir un répertoire
                    echo  "Veuillez saisir un répertoire où déplacer votre repertoire: "
                    read repertoire
                    chemin_rep=$(find / -type d -name "$repertoire" 2>/dev/null)
                    # Vérifier si le répertoire existe et est unique
                    if [ -n "$chemin_rep" ] &&[ "$(echo "$chemin_rep" | wc -l)" -eq 1 ]; then
                    # Vérifier si le répertoire ne contient pas un fichier de nom $p
                        if [ ! -e "$chemin_rep/$p" ]; then
                            echo "Répertoire valide."
                            mv "$p_B" "$chemin_rep"
                            echo "Vous venez de déplacer votre répertoire vers le répertoire spécifié : $repertoire"
                            break
                        else
                            echo "Le répertoire contient un fichier avec le nom $p. Veuillez réessayer."
                        fi
                   else
                        echo "Répertoire invalide. Veuillez réessayer."
                   fi 
                done
                ;;
            4)
		while true; do
                    # Demander à l'utilisateur de saisir un répertoire
                    echo  "Veuillez saisir un répertoire où déplacer votre fichier : "
                    read repertoire
                    chemin_rep=$(find / -type d -name "$repertoire" 2>/dev/null)
                    # Vérifier si le répertoire existe et est unique
                    if [ -n "$chemin_rep" ] &&[ "$(echo "$chemin_rep" | wc -l)" -eq 1 ]; then
                    # Vérifier si le répertoire ne contient pas un fichier de nom $p
                        if [ ! -e "$chemin_rep/$p" ]; then
                            echo "Répertoire valide."
                            mv "$p_A" "$chemin_rep"
                            echo "Vous venez de déplacer votre ficjier vers le répertoire spécifié : $repertoire"
                            break
                        else
                            echo "Le répertoire contient un fichier avec le nom $p. Veuillez réessayer."
                        fi
                    else
                        echo "Répertoire invalide. Veuillez réessayer."
                    fi 
                done
                ;;
            *)
                echo "Choix invalide. Aucune action effectuée.";;
        esac	    
    elif [ -d "$p_A" ] && [ -d "$p_B" ]; then
	true
    elif [ -f "$p_A" ] && [ -f "$p_B" ]; then
	local type="fichier ordinaire"
	if [ "$meta_p_A" = "$meta_p_B" ]; then 
            true
	else
            if grep "^$p_A $p_B\|^$p_B $p_A" journal > /dev/null 2>&1; then
                #si oui comparer ces metadonnées avec celles du fichier journal
                if [ "$meta_p_A" = "$meta_journal" ] && [ "$meta_p_B" != "$meta_journal" ] || [ "$meta_p_A" != "$meta_journal" ] && [ "$meta_p_B" = "$meta_journal" ]; then #cas ou l'une des metadonnées est identique avec celles du fichier journal
                    true
                else
#Demander à l’utilisateur s’il veut l’affichage ou non des différences( cas de 2 fichiers texte)
#ceci est un cas de gestion de conflit
                    local type_fichierA=$(file "$p_A")
                    local type_fichierB=$(file "$p_B")
                    if echo "$type_fichierA" | grep -e "text" > /dev/null 2>&1 && echo "$type_fichierB" | grep -e "text"  /dev/null 2>&1; then
                        echo "il s’agit de deux fichiers texte. saisissez 1 si vous souhaitez afficher le nombre de différences ou 2 si vous souhaitez ne rien faire"
                        read choix
                        case $choix in
			    1)diff "$p_A" "$p_B" | grep '^>' | echo "il y a en tout $(wc -l) differences entre les deux fichiers"
			      echo " nous allons afficher les differences"
			      diff "$p_A" "$p_B"
			      ;;
                            2)echo " vous avez choisi de ne rien faire ";;
                            *)echo "Choix invalide. Quitter.";;
                        esac
                    else 
                        echo "il ne s'agit pas d'un fichier texte"
                    fi
		            #afficher les différences de métadonnées 
		            echo "Saisissez 1 si vous souhaitez conserver les métadonnées du fichier $p_A ou 2 si vous souhaitez conserver les métadonnées du fichier $p_B"
                    read selection
                    case $selection in
                        1)
                            #conserver les métadonnées de A, faire une copie de p_A vers p_B et mettre à jour le fichier journal
                            cp "$p_A" "$p_B"
                            meta_journal="$meta_p_A"
                            sed -i "s#\(^$p_A $p_B\|^$p_B $p_A\).*#\1 $type $(date '+%m %d') $meta_journal#" journal
                            echo "operation 1 reussie" 
                            ;;
                        2) 
                            #conserver les métadonnées de B, faire une copie de p_B vers p_A et mettre à jour le fichier journal
                            cp "$p_B" "$p_A"
                            meta_journal="$meta_p_B"
                            sed -i "s#\(^$p_A $p_B\|^$p_B $p_A\).*#\1 $type $(date '+%m %d') $meta_journal#" journal
                            echo "operation 2 reussie " 
                            ;;
                        *) echo "Choix invalide. Quitter.";;
                    esac
                fi
            else
#Demander à l’utilisateur s’il veut l’affichage ou non des différences( cas de 2 fichiers texte)
#ceci est un cas de gestion de conflit
                local type_fichierA=$(file "$p_A")
                local type_fichierB=$(file "$p_B")
                if echo "$type_fichierA" | grep -e "text" > /dev/null 2>&1 && echo "$type_fichierB" | grep -e "text"  /dev/null 2>&1; then
                    echo "il s’agit de deux fichiers texte. saisissez 1 si vous souhaitez afficher le nombre de différences ou 2 si vous souhaitez ne rien faire"
                    read choix
                    case $choix in
			1)diff "$p_A" "$p_B" | grep '^>' | echo "il y a en tout $(wc -l) differences entre les deux fichiers"
			  echo " nous allons afficher les differences"
	                  diff "$p_A" "$p_B"
			  ;;
			2)echo " vous avez choisi de ne rien faire ";;
                        *)echo "Choix invalide. Quitter.";;
                    esac
                else 
                    echo "il ne s'agit pas d'un fichier texte"
                fi
                #afficher les différences de métadonnées 
                echo "Saisissez 1 si vous souhaitez conserver les métadonnées du fichier $p_A ou 2 si vous souhaitez conserver les métadonnées du fichier $p_B"
                read selection
                case $selection in
                    1)
                         #conserver les métadonnées de B, faire une copie de p_B vers p_A et creer une nouvelle entrée  le fichier journal car absente
                         cp "$p_A" "$p_B"
                         meta_journal="$meta_p_A"
		         echo "$p_A $p_B $type $(date '+%m %d') $meta_p_A" >> journal
                         echo "operation 1 reussie"
                         ;;
                    2) 
                         #conserver les métadonnées de B, faire une copie de p_B vers p_A et creer une nouvelle entrée  le fichier journal car absente
                         cp "$p_B" "$p_A"
                         meta_journal="$meta_p_B"
		         echo "$p_A $p_B $type $(date '+%m %d') $meta_p_B" >> journal
                         echo " operation 2 reussie " 
                         ;;
                    *) 
	                 echo "Choix invalide. Quitter."
                         ;;
                esac
            fi
        fi
    fi
}
interface_utilisateur "$fichier_A" "$fichier_B"
gestion_conflit "$fichier_A" "$fichier_B"
