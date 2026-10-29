# Installer SonarQube sur le Hub

## 1. Démarrer SonarQube

Docker doit être installé sur le serveur. Lancer :

```bash
docker run -d --name sonarqube \
  --restart unless-stopped \
  -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true \
  -p 9000:9000 \
  sonarqube:latest
```

Vérifier le démarrage :

```bash
docker ps --filter name=sonarqube
docker logs -f sonarqube
```

## 2. Ouvrir l'interface

Autoriser TCP/9000 dans le pare-feu du serveur, idéalement seulement depuis les IP autorisées, puis ouvrir :

```text
http://<IP-DU-HUB>:9000
```

Se connecter avec `admin` / `admin`, puis définir un nouveau mot de passe.

Pour Jenkins et l'analyse du projet, voir [`pulse/api/README.md`](../pulse/api/README.md).

## Arrêter ou supprimer

```bash
docker stop sonarqube
docker rm sonarqube
```
