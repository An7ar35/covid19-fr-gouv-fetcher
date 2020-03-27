# French governemnt Covid19 information and form fetcher script
 
### ENG

The [official french gouvernement page](https://www.gouvernement.fr/info-coronavirus) for the coronavirus is a good place to keep informed but (a) it's long and (b) doesn't indiquate what exactly has changed... So I wrote this little shell script (BASH) to fetch the page and the 2 forms that are required when going outside lest you end up with a rather hefty fine. The script just compares the HTML and the txt version of the forms with any previously downloaded ones and signals if there are any changes between the two versions.

This way you can `diff` the content when it does actually change and you don't have to re-read the entire thing over.

A cron-job or adding version control actions to the script is possible if you care to contribute. It's a quick and midly dirty socultion to a problem that will hopefully come to pass sooner rather than later.

Stay safe people.

Instruction: Just clone the repo and run the `fetch.sh` script from within. You could also make a cron job so that it does it regularly (every 6h for example).
 
### FR


Instruction: 

La page officielle du gouvernement français pour le coronavirus est un bon endroit pour se tenir informé mais (a) c'est un texte long et (b) n'indique pas ce qui a changé exactement ... J'ai donc écrit ce petit script shell (BASH) pour aller chercher la page et les 2 formulaires nécessaires pour sortir. Le script compare simplement le HTML et la version txt des formulaires avec ceux précédemment téléchargés et signale s'il y a des changements entre les deux versions.

De cette façon, vous pouvez `diff` (différencier) le contenu lorsqu'il change et vous n'avez pas à relire la totalité.

Un cron-job ou l'ajout d'actions `git` au script est possible si vous souhaitez contribuer. C'est une solution rapide et moyennement sale à un problème qui, espérons-le, finira plus tôt que tard.

Resté en bonne santé tous.

Instruction: il suffit de cloner le dépôt et d'exécuter le script `fetch.sh` dans le dossier. Vous pouvez également faire un cron job pour qu'il le fasse régulièrement (toutes les 6h par exemple).
