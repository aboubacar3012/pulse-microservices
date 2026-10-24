j'ai deja la version 2.Configuration dans votre Jenkinsfile mais quand je clique sur Stryker Mutation Report lapge ne s'affiche pas bien , et j'ai deja html publisher plugin énstalle

Cela est dû à la CSP (Content Security Policy) de Jenkins. Par sécurité, Jenkins bloque l'exécution des scripts JavaScript et le chargement des fichiers CSS externes dans les rapports HTML archivés.
Pour résoudre ce problème définitivement, vous devez assouplir la sécurité de Jenkins en exécutant une commande dans la console d'administration.

La solution : Modifier la politique de sécurité (CSP)

1. Connectez-vous à votre interface web Jenkins avec un compte administrateur.
2. Dans le menu de gauche, cliquez sur Administrer Jenkins (Manage Jenkins).
3. Faites défiler la page vers le bas et cliquez sur Console Script (Script Console).
4. Dans la grande zone de texte qui apparaît, copiez et collez la ligne suivante :

```bash
System.setProperty("hudson.model.DirectoryBrowserSupport.CSP", "sandbox allow-scripts; default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; img-src 'self' data:;")
```
5. Cliquez sur le bouton Faire le traitement (Run).

⚠️ Deux choses importantes à savoir après avoir appliqué la solution :

• Pour voir le changement : Allez sur votre pipeline, relancez un nouveau build de votre application, puis recliquez sur l'onglet Stryker Mutation Report. (Parfois, les rapports des anciens builds déjà générés restent bloqués, il faut un nouveau build pour valider).
• Au redémarrage de Jenkins : Cette commande s'efface si vous redémarrez votre serveur Jenkins. Si vous utilisez une instance Jenkins stable (ou un conteneur), il est fortement conseillé de rendre ce réglage permanent.
Si vous souhaitez rendre ce réglage permanent au démarrage de Jenkins, utilisez-vous Jenkins sous forme de conteneur Docker, via un service systemd (Linux APT), ou préférez-vous que l'on vérifie si le rapport Stryker s'affiche enfin correctement après cette commande ?