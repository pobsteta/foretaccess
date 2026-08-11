# BRIEF `nemetonshiny` — exposer les deux décisions de coût que le cœur ne peut pas trancher

> **À traiter dans une session de dev dédiée sur `/home/pascal/dev/nemetonshiny`**
> (un repo = une session). Repo concerné : `pobsteta/nemetonshiny`.
> Amont : `foretaccess`, branche `feat/cout-terrassement` (poussée).
> Fait suite à `BRIEF-dessertR-classement-osm-et-cout-terrassement.md` §5, qui annonçait le coût
> de terrassement « disponible, non activé ». Il l'est toujours — et c'est le sujet.
> **Rien d'urgent** : la chaîne actuelle est correcte, ce brief ajoute un choix.

## 1. Pourquoi ce brief

Le cœur a instrumenté deux façons de tarifer la pente et les a comparées sur DABO
(`specs/029-cout-terrassement.md` §7). Le banc établit que **le choix a des conséquences fortes,
pas qu'il a une bonne réponse** :

| | barème | terrassement |
|---|---:|---:|
| coût médian (domaine commun) | 45,0 €/m | 46,4 €/m |
| coût **moyen** | 64,6 €/m | **99,0 €/m** |
| routes créées / longueur | 37 / 6 931 m | 40 / 7 550 m |
| **recouvrement des deux tracés** | — | **44,1 %** |

Moins de la moitié du réseau est commune, pour des agrégats qui se ressemblent. Personne n'a jugé
lequel des deux jeux de tracés est le plus plausible sur le terrain — c'est un avis de
gestionnaire, pas une propriété du modèle. **D'où la décision : ne pas trancher dans le cœur, et
rendre le choix à l'utilisateur.**

## 2. Ce qu'il faut exposer — trois entrées, pas une

`surface_cout_construction()` prend désormais :

```r
surface_cout_construction(pre, cfg,
                          methode_pente = c("bareme", "terrassement"),
                          largeur_m     = 4,
                          pente_max_pct = NULL)
```

### 2.1 Méthode de tarification — `methode_pente`

`radioButtons`, défaut **barème**.

- **Barème** (défaut) — quatre classes de pente, échelle en vigueur. Discontinue : 65 €/m d'écart
  entre 34,9 % et 35,1 %. Aveugle à la largeur de plateforme.
- **Terrassement** — volumes de déblai / remblai chiffrés au m³. Continu, et **le seul des deux
  qui tienne compte de la largeur** : le volume croît comme son carré.

Libellé d'aide suggéré : « Le terrassement chiffre un volume de terre ; le barème applique une
grille par classe de pente. Les deux donnent des coûts médians comparables mais **des tracés
différents à plus de la moitié**. »

### 2.2 Largeur de plateforme — `largeur_m`

`numericInput`, défaut 4 m, plage 2,5–6.

**Elle n'a d'effet qu'avec le terrassement** — le griser en mode barème serait honnête. Elle doit
venir de la largeur visée par le gestionnaire, pas d'une constante : c'est précisément ce que le
barème ne sait pas représenter.

### 2.3 Pente maximale constructible — `pente_max_pct`

`numericInput`, défaut **60 %**.

**C'est l'entrée à ne pas oublier, et l'ordre compte** : sans elle, choisir « terrassement »
décidait *aussi* du plafond, en silence. Le barème s'arrête à 60 % par sa dernière classe ; le
terrassement va jusqu'à la pente du talus de déblai (100 %) et ouvrait ainsi **5,02 % du massif
DABO** — 67 632 cellules entre 60 et 100 % de pente — sans que personne l'ait demandé.

Le cœur reprend maintenant par défaut le plafond implicite du barème, de sorte que changer de
méthode ne change **que la tarification**. Passer le plafond au-dessus de 60 % est une décision
distincte, qui doit se voir.

Libellé d'aide suggéré : « Au-delà de ce seuil, aucune route n'est tracée. L'augmenter ouvre du
terrain que le barème refusait : le coût y est très élevé mais **fini**, donc dissuasif et non
interdit — dans un corridor sans alternative, le solveur le prendra. »

## 3. Ce qu'il ne faut pas faire

- **Ne pas basculer le défaut** sur « terrassement ». Le calage des prix au m³ n'est pas un relevé
  de devis : il est obtenu par inversion d'un plafond de subvention (spec 029, §Prix). Tant qu'un
  gestionnaire n'a pas fourni de barème réel, le terrassement est un modèle mieux formé, pas un
  modèle mieux calé.
- **Ne pas exposer `pente_max_pct` sans son avertissement.** Un `numericInput` nu invite à monter
  le chiffre pour « avoir plus de solutions ».
- **Ne pas comparer deux runs sur leurs totaux.** C'est le piège que le banc a documenté : longueur
  à 9 % près, trois routes d'écart, et 44 % de géométrie commune. Si l'app affiche un comparatif,
  qu'il porte sur la géométrie.

## 4. Invalidation du cache

Les trois entrées changent le résultat. Elles doivent entrer dans la clé du cache desserte, au même
titre que `skidding_m` et le moteur — sinon un changement de méthode rendra le réseau précédent
sans recalcul. Le mécanisme d'invalidation ajouté pour `pondere_cout` (`meta$pondere_cout`) est le
bon endroit.

## 5. Ce que le cœur fournit, et ce qu'il ne fournit pas

**Fourni** : les trois arguments, testés ; le plafond appliqué aux deux méthodes ; la garantie que
la géométrie garde le dernier mot — au-delà du talus de déblai, aucun plafond ne rend une cellule
constructible.

**Non fourni** : un barème de prix au m³ digne de ce nom, et un avis sur lequel des deux jeux de
tracés est le meilleur. Le second ne viendra pas du cœur — il viendra du terrain, ou pas.
