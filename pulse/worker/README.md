# santu/pulse-worker

Worker de **Pulse** développé avec Java 21 et Spring Boot. Il consomme les votes de la liste Redis `votes` et les enregistre dans Postgres.

## Fonctionnement

- Blocage sur `BRPOP` de la file `votes` (attente de 5 secondes).
- Validation du JSON et de l’outil (`docker`, `ansible`, `kubernetes`, `linux`, `git`, `terraform`, `jenkins`, `aws`).
- Insertion d’une ligne dans `votes` avec l’outil et le `session_id`.
- Création/mise à niveau de la table et de ses index au démarrage.
- Nouvelle tentative avec journalisation en cas d’indisponibilité de Redis ou Postgres.

Le worker est un processus interne, sans port HTTP ni Service Kubernetes.

## Prérequis

- JDK 21 ou plus récent
- Maven 3.9+
- Redis sur `localhost:6379` et Postgres sur `localhost:5432` pour lancer le worker localement

## Configuration

| Variable                     | Défaut local                                    | Compose / cluster                                    |
| ---------------------------- | ----------------------------------------------- | ---------------------------------------------------- |
| `REDIS_HOST`                 | `localhost`                                     | `redis`                                              |
| `REDIS_PORT`                 | `6379`                                          | `6379`                                               |
| `DATABASE_URL`               | `postgresql://pulse:pulse@localhost:5432/pulse` | URL PostgreSQL vers `db:5432/pulse`                  |
| `SPRING_DATASOURCE_URL`      | —                                               | URL JDBC alternative, prioritaire sur `DATABASE_URL` |
| `SPRING_DATASOURCE_USERNAME` | `pulse`                                         | Utilisateur JDBC alternatif                          |
| `SPRING_DATASOURCE_PASSWORD` | `pulse`                                         | Mot de passe JDBC alternatif                         |

`DATABASE_URL` accepte les formes `postgres://`, `postgresql://` et `jdbc:postgresql://`. Pour une URL PostgreSQL classique, le worker la convertit en URL JDBC. Les identifiants peuvent aussi être fournis séparément avec les variables `SPRING_DATASOURCE_*`.

## Lancer le projet avec Maven

Depuis la racine du dépôt, démarrer d’abord Redis et Postgres si nécessaire :

```bash
docker compose -f pulse/docker-compose.yml up -d redis db
```

Puis lancer l’application en mode développement :

```bash
cd pulse/worker
mvn spring-boot:run
```

Le worker utilise par défaut les services locaux et reste actif tant qu’il tourne. Il attend que Postgres et Redis soient disponibles, puis consomme la file `votes`. Arrêter avec `Ctrl+C`.

Pour configurer les connexions explicitement :

```bash
REDIS_HOST=localhost \
REDIS_PORT=6379 \
SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5432/pulse \
SPRING_DATASOURCE_USERNAME=pulse \
SPRING_DATASOURCE_PASSWORD=pulse \
mvn spring-boot:run
```

## Tests et couverture

La suite comprend des tests du parsing des messages, de la configuration PostgreSQL, du traitement des votes, de l’initialisation du schéma et des scénarios de reprise après erreur Redis/Postgres.

```bash
cd pulse/worker

# Exécuter tous les tests unitaires
mvn test

# Nettoyer, tester, générer le rapport et vérifier le seuil de couverture
mvn clean verify
```

JaCoCo impose au minimum **89 % de couverture des lignes** sur l’ensemble du code de production. `mvn verify` échoue si le seuil n’est pas atteint.

Rapport HTML après les tests : `target/site/jacoco/index.html`.

## Packager et exécuter le JAR

```bash
cd pulse/worker

# Compiler et générer target/pulse-worker.jar
mvn clean package

# Vérifier aussi le seuil de couverture (recommandé avant livraison)
mvn clean verify

# Lancer le JAR exécutable Spring Boot
java -jar target/pulse-worker.jar
```

Le JAR a besoin des mêmes variables de configuration que `mvn spring-boot:run`.

## Build et exécution Docker updated

Le build multi-étape compile et teste l’application avec Java 21, puis l’exécute sur une image JRE légère sans privilèges root :

```bash
cd pulse/worker
docker build -t santu/pulse-worker .
docker run -d --name worker --network pulse-net \
  -e REDIS_HOST=redis \
  -e DATABASE_URL=postgresql://pulse:pulse@db:5432/pulse \
  santu/pulse-worker
```

Pour les nœuds Kubernetes `linux/amd64`, construire l’image depuis ce dossier avec `docker buildx build --platform linux/amd64 -t santu/pulse-worker .`.

## Déploiement Kubernetes avec les scripts réutilisables

Les scripts `k8s.sh` et `k8s-rollout-status.sh` sont conçus pour être copiés dans un microservice qui suit la même convention de manifests :

- un dossier `k8s/` contenant les manifests à appliquer ;
- un `k8s/deployment.yaml` contenant le Deployment à surveiller.

Depuis le dossier du microservice et avec `kubectl` déjà configuré sur le cluster cible :

```bash
bash k8s.sh
bash k8s-rollout-status.sh
```

`k8s.sh` déploie à chaque exécution **tous les manifests présents dans `k8s/`, y compris ses sous-dossiers**. Il vérifie que `kubectl` et les manifests attendus sont présents, fait une validation locale puis une validation côté API Kubernetes (`--dry-run=server`) avant l’application réelle. Après l’application, il redémarre le Deployment défini dans `k8s/deployment.yaml` pour forcer le téléchargement d’une image `latest` nouvellement publiée. `k8s-rollout-status.sh` vérifie que la ressource existe, attend la fin du rollout puis attend explicitement la condition `Available`, avec un délai maximal de 180 secondes pour chaque attente.

Toute erreur (manifest invalide, accès cluster insuffisant, image non téléchargeable, pod non prêt ou délai dépassé) arrête le script avec un code non nul. Aucun rollback automatique n’est effectué. Les scripts sont adaptés à la convention de manifests ci-dessus; les noms Kubernetes restent dans les fichiers YAML et ne nécessitent pas de variables shell.

L’image `latest` est conservée pour correspondre au manifeste actuel. Pour un déploiement de production, privilégier un tag immuable (par exemple le SHA du commit) ou un digest d’image et mettre à jour le manifeste vers cet artefact précis.

## Logs

```bash
docker logs -f worker
```
