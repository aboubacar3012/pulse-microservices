# SonarQube — serveur hub

Installation de **SonarQube** sur le hub (analyse statique / SAST).  
CI Jenkins : voir [`pulse/api/README.md`](../../pulse/api/README.md) (stage `SonarQube`, credential `sonar-token`).

## Lancer le conteneur

```bash
docker run -d --name sonarqube \
  -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true \
  -p 9000:9000 \
  sonarqube:latest
```

`SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true` évite l’échec Elasticsearch sur une petite VM (mémoire / `vm.max_map_count`).

## Accès

|                         |                                                         |
| ----------------------- | ------------------------------------------------------- |
| URL                     | `http://<host-hub>:9000`                                |
| Identifiants par défaut | `admin` / `admin` (changement demandé au premier login) |

Exemples : IP publique Lightsail, ou un enregistrement DNS du type `sonar.santu.io` si tu en as un.

## Arrêt

```bash
docker stop sonarqube
docker rm sonarqube
```
