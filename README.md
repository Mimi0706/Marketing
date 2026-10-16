# Carte des EHPAD de France

Carte interactive de tous les EHPAD (établissements d'hébergement pour personnes âgées dépendantes) de France métropolitaine et d'outre-mer.

- Recherche par nom, ville, code postal ou adresse
- Filtre par département, habilitation à l'aide sociale, hébergement temporaire et accueil de jour
- Fiche de chaque établissement : adresse, téléphone, capacité (places permanentes, hébergement temporaire, accueil de jour), itinéraire, numéro FINESS

> La capacité affichée est le nombre total de places installées, pas le nombre de places libres : aucune donnée publique ne donne les disponibilités en temps réel.

## Fichiers

| Fichier | Rôle |
|---|---|
| `index.html` | Le site (Leaflet + OpenStreetMap) |
| `ehpad.js` | Les données des EHPAD, générées depuis FINESS |
| `build-data.ps1` | Script de mise à jour des données |

## Mettre à jour les données

Le script télécharge la dernière extraction FINESS géolocalisée sur data.gouv.fr, garde les EHPAD (catégorie 500), convertit les coordonnées en GPS et régénère `ehpad.js` :

```powershell
powershell -ExecutionPolicy Bypass -File build-data.ps1
```

## Source des données

- [FINESS – Extraction du fichier des établissements](https://www.data.gouv.fr/fr/datasets/finess-extraction-du-fichier-des-etablissements/) (adresses et coordonnées)
- [FINESS – Extraction des équipements sociaux et médico-sociaux](https://www.data.gouv.fr/fr/datasets/finess-extraction-des-equipements-sociaux-et-medico-sociaux/) (capacités)

Ministère de la Santé, Licence Ouverte / Etalab.
Fonds de carte © contributeurs [OpenStreetMap](https://www.openstreetmap.org/copyright).
