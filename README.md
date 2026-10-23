# Carte des EHPAD de France

Site d'aide au choix d'un EHPAD (établissement d'hébergement pour personnes âgées dépendantes) pour un proche, couvrant la France métropolitaine et l'outre-mer.

- Carte schématique de la France (contours des départements, outre-mer en encarts) : clic sur un département pour zoomer et filtrer ; points colorés au choix par prix, note HAS ou statut
- Recherche par ville, code postal, département ou nom
- Filtres : département, budget mensuel, note HAS, statut, besoins (unité Alzheimer, infirmier de nuit, hébergement temporaire, accueil de jour, aide sociale), affichés en étiquettes que l'on retire d'un clic
- Tri par prix, note HAS, capacité ou nom
- Fiche détaillée : chiffres clés, prix détaillés, évaluation HAS par thème, personnel et soins comparés à la moyenne, places et admission, dépendance du département ; explications du vocabulaire (GIR, HAS, ETP…)
- « Ma sélection » : comparer jusqu'à 4 EHPAD côte à côte (sélection gardée dans le navigateur)
- Adapté au téléphone, au clavier et au mode sombre

> Niveau de qualité HAS : A = démarche qualité avancée, B = structurée, C = partielle, D = insuffisante. Les EHPAD sont évalués tous les 5 ans par un organisme indépendant ; tous n'ont pas encore d'évaluation publiée.

> Le prix mensuel affiché est une estimation : (prix de la chambre seule + tarif dépendance GIR 5-6) × 30 jours, d'après les prix déclarés à la CNSA.

> La capacité affichée est le nombre total de places installées, pas le nombre de places libres : aucune donnée publique ne donne les disponibilités en temps réel.

## Fichiers

| Fichier | Rôle |
|---|---|
| `index.html` | Le site (carte schématique en D3) |
| `stats.html` | Page de statistiques : description, jointure départementale, 12 tests d'hypothèses, régression multiple (calculs refaits à l'ouverture) |
| `stats-lib.js` | Fonctions statistiques (Mann-Whitney, Kruskal-Wallis, Welch, Khi², Spearman, moindres carrés, logistique) |
| `deps.js` | Noms des départements, partagés par la carte et les statistiques |
| `departements.js` | Contours simplifiés des départements ([france-geojson](https://github.com/gregoiredavid/france-geojson), d'après IGN / Etalab) |
| `ehpad.js` | Les données des EHPAD, générées depuis FINESS |
| `build-data.ps1` | Script de mise à jour des données |
| `collect-indicateurs.ps1` | Collecte les indicateurs de l'annuaire officiel (personnel, médecin, chambres) dans `indicateurs.json` |
| `indicateurs.json` | Indicateurs collectés (cache, lu par `build-data.ps1`) |

## Mettre à jour les données

Le script télécharge les dernières versions des sources ci-dessous sur data.gouv.fr, garde les EHPAD (catégorie FINESS 500), convertit les coordonnées en GPS et régénère `ehpad.js` (compter environ 5 minutes) :

```powershell
powershell -ExecutionPolicy Bypass -File build-data.ps1
```

Les indicateurs de personnel (taux d'encadrement, turnover, absentéisme, médecin coordonnateur, infirmier de nuit, chambres, unités Alzheimer/PASA) viennent de l'annuaire officiel [pour-les-personnes-agees.gouv.fr](https://www.pour-les-personnes-agees.gouv.fr/annuaire-ehpad-et-maisons-de-retraite) (CNSA, Licence Ouverte Etalab 2.0), interrogé EHPAD par EHPAD. Les lancer avant `build-data.ps1` (environ 1 heure pour toute la France, reprise possible) :

```powershell
powershell -ExecutionPolicy Bypass -File collect-indicateurs.ps1            # tous les EHPAD pas encore collectés
powershell -ExecutionPolicy Bypass -File collect-indicateurs.ps1 -Dep 69    # un seul département
```

## Source des données

- [FINESS – Extraction du fichier des établissements](https://www.data.gouv.fr/fr/datasets/finess-extraction-du-fichier-des-etablissements/) (adresses et coordonnées)
- [FINESS – Extraction des équipements sociaux et médico-sociaux](https://www.data.gouv.fr/fr/datasets/finess-extraction-des-equipements-sociaux-et-medico-sociaux/) (capacités)
- [Prix hébergement et tarifs dépendance des EHPAD – données brutes](https://www.data.gouv.fr/fr/datasets/prix-hebergement-et-tarifs-dependance-des-ehpad-donnees-brutes/) (prix, CNSA)
- [FINESS – Extraction des entités juridiques](https://www.data.gouv.fr/fr/datasets/finess-extraction-des-entites-juridiques/) (gestionnaires et statuts)
- [Résultats d'évaluation des ESSMS](https://www.data.gouv.fr/fr/datasets/resultats-devaluation-des-etablissements-et-services-sociaux-et-medico-sociaux-essms/) (qualité, HAS)
- [Valeurs moyennes du GIR moyen pondéré par département](https://www.data.gouv.fr/datasets/valeurs-moyennes-du-gir-moyen-pondere-par-departement) (dépendance moyenne des résidents, CNSA ; non publié par EHPAD)

Ministère de la Santé, CNSA et HAS, Licence Ouverte / Etalab.
Fonds de carte © contributeurs [OpenStreetMap](https://www.openstreetmap.org/copyright).
