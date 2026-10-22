# Carte des EHPAD de France

Carte interactive de tous les EHPAD (établissements d'hébergement pour personnes âgées dépendantes) de France métropolitaine et d'outre-mer.

- Recherche par nom, ville, code postal ou adresse
- Filtre par département, budget mensuel, statut (public, privé non lucratif, privé commercial), niveau de qualité HAS, habilitation à l'aide sociale, hébergement temporaire et accueil de jour
- Tri par ville, prix, nombre de places ou qualité HAS
- Fiche de chaque établissement : adresse, téléphone, statut et gestionnaire, évaluation qualité HAS (niveau A à D, critères impératifs, notes par thème), capacité (places permanentes, hébergement temporaire, accueil de jour), prix (chambre seule, double, aide sociale, temporaire, tarifs dépendance GIR), lien vers les avis Google, itinéraire, numéro FINESS

> Niveau de qualité HAS : A = démarche qualité avancée, B = structurée, C = partielle, D = insuffisante. Les EHPAD sont évalués tous les 5 ans par un organisme indépendant ; tous n'ont pas encore d'évaluation publiée.

> Le prix mensuel affiché est une estimation : (prix de la chambre seule + tarif dépendance GIR 5-6) × 30 jours, d'après les prix déclarés à la CNSA.

> La capacité affichée est le nombre total de places installées, pas le nombre de places libres : aucune donnée publique ne donne les disponibilités en temps réel.

## Fichiers

| Fichier | Rôle |
|---|---|
| `index.html` | Le site (Leaflet + OpenStreetMap) |
| `ehpad.js` | Les données des EHPAD, générées depuis FINESS |
| `build-data.ps1` | Script de mise à jour des données |

## Mettre à jour les données

Le script télécharge les dernières versions des sources ci-dessous sur data.gouv.fr, garde les EHPAD (catégorie FINESS 500), convertit les coordonnées en GPS et régénère `ehpad.js` (compter environ 5 minutes) :

```powershell
powershell -ExecutionPolicy Bypass -File build-data.ps1
```

## Source des données

- [FINESS – Extraction du fichier des établissements](https://www.data.gouv.fr/fr/datasets/finess-extraction-du-fichier-des-etablissements/) (adresses et coordonnées)
- [FINESS – Extraction des équipements sociaux et médico-sociaux](https://www.data.gouv.fr/fr/datasets/finess-extraction-des-equipements-sociaux-et-medico-sociaux/) (capacités)
- [Prix hébergement et tarifs dépendance des EHPAD – données brutes](https://www.data.gouv.fr/fr/datasets/prix-hebergement-et-tarifs-dependance-des-ehpad-donnees-brutes/) (prix, CNSA)
- [FINESS – Extraction des entités juridiques](https://www.data.gouv.fr/fr/datasets/finess-extraction-des-entites-juridiques/) (gestionnaires et statuts)
- [Résultats d'évaluation des ESSMS](https://www.data.gouv.fr/fr/datasets/resultats-devaluation-des-etablissements-et-services-sociaux-et-medico-sociaux-essms/) (qualité, HAS)

Ministère de la Santé, CNSA et HAS, Licence Ouverte / Etalab.
Fonds de carte © contributeurs [OpenStreetMap](https://www.openstreetmap.org/copyright).
