# Pilote fractal Trois-Tiers : note d'exploration

*Agent « Pilote fractal », 19 novembre 2026. Mode lecture seule : rien n'a été modifié, publié ni activé.*

## 1. Ce qui existe aujourd'hui

Quatre des cinq ressources ont pu être lues. Le **Cadre de coordination des missions** n'a pas pu être ouvert : erreur réseau répétée (accès bloqué depuis ce poste). Il n'est donc pas analysé ici.

| Pilote | Ce qu'il fait | Où il garde ses données | Plusieurs utilisateurs ? |
|---|---|---|---|
| **Pilote 3/3** | Cockpit complet : Tableau, Ma journée, Hebdo, Missions, Planning, Salle d'attente, Agents & journal, recherche, fiches | Base partagée de l'artefact : tâches, missions, journal, propositions, absences, points hebdo, plans du jour, réglages | Oui. Chacun choisit son nom (« Je suis ») et chaque modification est signée. Un compte qui ne fait que consulter voit un avertissement « lecture seule ». |
| **Pilote du pivot** | Tableau et planning du gros chantier : cinq couloirs (P-A, Europe, Instruments, Eveline, Yan), tâches, statuts, sous-tâches, congés BE/FR | Tâches écrites dans le code, plus une couche de modifications dans la base partagée | Oui (édition en direct), sans signature ni journal |
| **Pilote territorial Poiethic** | Même ossature que le pivot : quatre couloirs (AO, IA, CTG, RTE), filtre par territoire, notes, échéances J-x | Base partagée uniquement : il n'y a plus de tâches écrites dans le code | Oui (édition en direct), sans journal |
| **Configurateur AMO** | Calculateur de parcours et de budget : 11 étapes, environ 50 modules, packs, 7 scénarios dont La Louvière (Palace), import de documents analysés par Claude | Rien n'est conservé : l'état est perdu à la fermeture de la page | Non, c'est un outil individuel |

**Points communs.** Les Pilotes partagent la même structure de tâche : titre, couloir ou chantier, responsables, dates, jalon, statut (à faire, en cours, bloqué, fait), sous-tâches et notes. Ils ont tous une vue Tableau et une vue Planning hebdomadaire avec les congés scolaires, et affichent une ligne d'état de la connexion. Le Pivot et Poiethic sont des « clones » d'une même recette, ce qui montre que la logique fractale a déjà commencé de façon artisanale.

**Ce qui est propre au Pilote 3/3** et en fait le seul véritable cockpit :
- une **flotte de 8 agents planifiés**. Cinq tournent dans le cloud : PV, Disponibilités, Missions & Courrier, Hebdo, Newsletter et Cohérence. Trois demandent le Mac de l'équipe allumé : Element, Relances (Infomaniak) et WhatsApp, ce dernier en lecture seule, sans marquer les messages comme lus ;
- un **journal** où chaque changement fait par un agent est consigné et **s'annule en un clic** ;
- une **salle d'attente** pour les cas réservés : suppression, fusion, changement de titre ou de chantier, réouverture, conflit. N'importe quel membre peut valider, ajuster ou rejeter ;
- des **fiches mission** avec contexte, demandes, prochaines actions, tâches liées, cinq dernières sources (mail, PV, Element, WhatsApp, Drive) et référent·e. Le type de mission est soit « Marché public », soit « Autre » ;
- une **« Ma journée »** et une analyse de PV faites par Claude depuis la page, un agent Cohérence qui repère les doublons et sauvegarde la base, et un champ « estimation en heures » sur les tâches.

**Ce qui manque partout** : un module « décisions » distinct (le 3/3 n'a qu'une étiquette « Décision » dans le journal), des « questions en suspens », un suivi du **temps passé par rapport au budget** (aucun drapeau orange ou rouge), la ventilation par **rôle** (prestation, apport d'affaires, suivi client, coordination) et toute **zone de confidentialité** : tous les membres d'un Pilote voient tout.

## 2. La recette de base proposée

Un Pilote = **un socle commun + des modules qu'on allume ou qu'on éteint**. La base de départ est le Pilote 3/3, le plus abouti, débarrassé de ce qui est propre à l'équipe : membres, chantiers et agents écrits dans le code. Le 3/3 range déjà membres, chantiers et sources de PV dans des réglages partagés, ce qui rend ce nettoyage réaliste.

**Socle, toujours présent :**
1. **Journal de bord.** Il s'affiche en premier quand on ouvre le Pilote : ce qui a changé depuis la dernière visite, qui l'a fait (humain ou agent), un bouton d'annulation. C'est l'« IA invisible » : on lit le résultat, on ne pilote pas l'IA.
2. **Tâches et missions** : tableau, planning et fiches.
3. **Salle d'attente** : ce que les agents proposent sans pouvoir l'appliquer eux-mêmes.
4. **Recherche** et **liens directs** vers chaque fiche.

**Modules optionnels :**
- **Décisions** : qui a décidé, quand, à partir de quelle source, et quelle mission ou tâche est concernée.
- **Questions en suspens** : la question, à qui elle est posée, depuis quand, la relance prévue.
- **Garde-fou de temps**, sur le modèle décrit pour La Louvière : un budget d'heures par mission ou par rôle, comparé au temps passé. **Drapeau orange au-delà de 50 % de dépassement, alerte rouge ensuite.** Le seuil exact de l'alerte rouge reste à fixer par PA.
- **Rôles** : chaque personne est rattachée à la mission avec un rôle (prestation, apport d'affaires, gestion et suivi client, coordination) et, si on le souhaite, des heures ou une part de rémunération.
- **Hebdo**, ordre du jour de la réunion, comme dans le 3/3.
- **Sources** : dossier Drive, salons WhatsApp ou Element, adresses mail transférées.
- **Disponibilités** : congés et absences.
- **Pont vers CTG** (voir la section 6).

**Réglages d'un Pilote** : nom, membres, couloirs ou chantiers, calendrier de congés (BE, FR ou les deux), cadence des réunions, sources branchées, modules allumés, niveaux de confidentialité, Pilote parent vers lequel remontent les informations.

## 3. La fiche d'identité : le questionnaire d'entrée

Chaque réponse règle un ou plusieurs paramètres du nouvel espace.

| Question | Ce que la réponse active |
|---|---|
| Quel type d'espace ? (mission, groupe de travail, fonction support, partenaire) | Le gabarit : mission → décisions, questions, temps, rôles ; groupe de travail → décisions, hebdo ; support → tâches, disponibilités |
| Nom, territoire, structure cliente ou partenaire | Le titre, l'étiquette territoire et la fiche publique |
| Qui en fait partie, avec quel rôle ? | Les membres, les rôles et les droits sur les niveaux de confidentialité |
| Y a-t-il des personnes externes ? | Le recueil des consentements avant toute captation ; les externes sont exclus par défaut du niveau « interne » |
| Budget en heures ou en euros, par rôle ? | Le garde-fou de temps et le calcul des seuils orange et rouge |
| Dates de début et de fin, jalons | Le planning et les échéances J-x |
| Où se passent les échanges ? (dossier Drive, WhatsApp, Element, mails) | Les sources que les agents ont le droit de lire, une à une, sur consentement |
| Rythme de réunion et où sont les notes ? | Le module hebdo et l'agent PV |
| Que peut-on rendre public ? | La part publique (titre, résumé, personnes, structures) et la création ou non d'une quête CTG |
| De quel Pilote parent dépend l'espace ? | Le sens de remontée vers le 3/3, le Bureau ou le tableau OA |

Pour une mission AMO, ce questionnaire peut **reprendre les critères du Configurateur AMO** (porteur, bâti, surface, vocations, enveloppe), qui en contient déjà la moitié. Le parcours choisi devient alors la liste des tâches de départ et le budget du garde-fou.

## 4. Les déclinaisons

| Pilote | Contenu principal | Ce qui change |
|---|---|---|
| **3/3 (coordination)** | Fonctions support, gouvernance, Europe, marché public | Existe déjà. Il reçoit en plus une synthèse de chaque mission et de chaque groupe de travail. |
| **Bureau / réseau d'accompagnants** | **Liste des missions en cours**, rôles, temps, alertes | Nouveau. Même présentation et même journal que le 3/3, avec une fiche par mission. Les tâches internes de l'équipe en sont exclues. |
| **Groupes de travail** | Décisions, questions, prochaines réunions | Pas de budget ni de rôles commerciaux ; une part publique plus large |
| **Tableau OA** | Vues agrégées en lecture seule : nombre de missions, alertes, décisions | Aucune édition. Il ne lit que des données au niveau « membres » ou « public ». |

**Un Pilote par groupe de travail, ou un seul pour tous ?**
- **A. Un Pilote unique « Groupes de travail »**, un couloir par groupe. Simple et une seule base. En revanche, tout le monde voit tout, sauf à ajouter un filtrage dont les artefacts ne garantissent pas l'étanchéité (voir la section 7).
- **B. Un Pilote par groupe**, copié depuis la recette. L'étanchéité vient du partage même de l'artefact. En revanche, il faut répliquer les correctifs dans chaque copie et créer un agent de remontée par groupe.
- **C. Un Pilote unique tant que les groupes ne traitent rien de confidentiel**, puis on en sort un groupe dès qu'il en a besoin. C'est un compromis pragmatique.

## 5. La captation

Classement par faisabilité, de la plus simple à la plus délicate, et par risque. La faisabilité s'appuie sur ce qui tourne déjà dans le 3/3.

1. **Notes de réunion et PV dans Google Docs.** Faisable et éprouvé : l'agent PV fonctionne déjà. Risque faible, les notes étant écrites pour être partagées.
2. **Dossiers Drive des missions.** Faisable : le connecteur Google Drive est disponible, et le 3/3 lit déjà des fichiers. Risque moyen : les dossiers contiennent des documents de tiers.
3. **Mails transférés volontairement à une adresse dédiée.** Faisable : l'agent Missions & Courrier le fait déjà. Risque moyen, mais la personne qui transfère choisit ce qu'elle partage.
4. **Element.** Faisable, mais dépend d'un Mac allumé et d'un compte connecté. Risque moyen.
5. **Appels Zoom.** Aucun connecteur Zoom n'a été repéré dans cette session. Il faudrait passer par les transcriptions déposées dans le Drive. Risque élevé : c'est la voix de participants souvent externes.
6. **WhatsApp.** Fonctionne aujourd'hui via WhatsApp Web, l'extension Chrome et un Mac allumé, en lecture seule. C'est **la source la plus fragile** (dépendance technique, conditions d'utilisation de WhatsApp) **et la plus risquée** (groupes mêlant le réseau et des externes, conversations informelles).

**Garde-fous proposés :**
- **Consentement par source et par espace**, recueilli par la fiche d'identité. Les externes sont informés et peuvent refuser ; le groupe ou le dossier concerné est alors exclu.
- **Les agents étiquettent, ils ne publient pas.** Rien ne passe au niveau « public » sans validation humaine dans la salle d'attente.
- **Une seule part publique** : titre, résumé, personnes et structures, avec l'accord des personnes nommées.
- **Une trace de la source** pour chaque information, comme le font déjà les fiches mission, afin de pouvoir retirer une information à la demande (droit d'effacement prévu par le RGPD).

## 6. Le lien avec ChangeTheGame

Le code de CTG contient **deux serveurs MCP**, des outils qui permettent à Claude d'agir dans CTG :
- un **serveur personnel** (« changethegame »), qui agit au nom de la personne connectée : profil, quêtes, guildes, tâches personnelles ; il **ne crée pas de quête** ;
- un **serveur de guilde** (« guild-mcp »), accessible par une **clé propre à la guilde**. Les clés sont créées par les administrateurs de la guilde, avec des droits « lecture » ou « écriture ». Ses outils utiles ici : **créer une quête** (en brouillon par défaut), **créer une sous-tâche** (avec responsable, échéance et priorité), mettre à jour le statut d'une sous-tâche, joindre un lien, lister les décisions et voter, créer un événement, publier un message, consigner une contribution, attribuer de l'XP, inviter un membre.

Créer une quête et ses sous-tâches pour la guilde Trois-Tiers depuis un Pilote est donc **techniquement possible dès aujourd'hui**, avec une clé « écriture » de la guilde.

**Ce qui manque pour une synchronisation mission = quête :**
- aucun outil de **modification d'une quête** (titre, résumé, statut, clôture) n'a été trouvé, seulement la création ;
- aucun champ d'**identifiant externe** n'a été trouvé pour relier une mission du Pilote à sa quête. Le plus simple serait de stocker l'identifiant de la quête dans la fiche mission ;
- aucun outil de création de décision ni de « question » n'a été trouvé, seulement la lecture et le vote ;
- les **rôles** (prestation, apport d'affaires…) et le **temps budgété** ne sont pas présents dans les sous-tâches. « Consigner une contribution » pourrait porter le temps passé, à vérifier ;
- la quête n'a, à ma connaissance du code lu, pas de niveau « visible des seuls accompagnants de la mission ». Le champ « universe_visibility » existe, mais il ne semble pas servir à la confidentialité. Il faudrait donc **n'envoyer vers CTG que la part publique**.

Branchement possible : la page Pilote peut appeler un serveur MCP (le 3/3 déclare déjà Drive et Claude Code Remote), ou bien un agent planifié pousse vers CTG après validation. Il faut aussi décider où est stockée la clé de la guilde : jamais dans le code de la page.

## 7. Limites des artefacts comme cockpits, et alternatives

**Ce qui fonctionne** : une base partagée en temps réel, l'édition par plusieurs personnes, des agents planifiés qui écrivent dans la base, l'appel à Claude et aux connecteurs depuis la page.

**Les limites :**
- **Accès** : on est éditeur ou lecteur de **tout** l'artefact. Le 3/3 rappelle que le propriétaire doit inviter chaque compte comme éditeur et désactiver le lien public. Les artefacts n'offrent **pas de permissions par ligne** : un filtre dans la page masque, mais ne protège pas, car la donnée reste lisible par qui a accès à la base.
- **Identité** : le nom choisi via « Je suis » est déclaratif. Il trace qui a fait quoi, mais il n'authentifie personne.
- **Dépendance au compte de l'équipe** : les agents tournent depuis ce compte, et trois d'entre eux depuis un Mac allumé.
- **Copies** : chaque clone diverge. Le Pivot et Poiethic ont déjà perdu le journal et la salle d'attente du 3/3.
- **Taille** : le 3/3 fait déjà 217 Ko dans un seul fichier, ce qui le rend lourd à faire évoluer.
- **Externes** : il faut un compte claude.ai pour éditer.

**Alternatives :**
- **CTG lui-même** comme cockpit des missions publiques ou membres : il a déjà des comptes, des rôles et des règles d'accès dans sa base.
- **Un découpage par niveau** : un artefact par cercle de confidentialité, alimenté par un agent qui ne recopie que ce que le niveau autorise.
- À plus long terme, une base dédiée avec règles d'accès par ligne (comme celle de CTG), les Pilotes devenant de simples vues.

## 8. Câblage Drive, logique fractale, Pilote des accompagnants et étiquetage *(précisions de PA)*

### 8.1 La mission câblée dans le Drive : la recette de base d'une mission

L'arborescence créée par l'agent devient le **squelette standard** de toute mission, par exemple « En cours - Tiers-lieu du Palace (La Louvière) » rangé dans « Missions Accompagnement » :
- **01 Pilotage de la mission** : fiche d'identité, budget, rôles ;
- **02 Offre, contrat et facturation** : niveau interne uniquement ;
- **03 Documents de la Ville et des partenaires** : documents de tiers, à usage interne à la mission ;
- **04 Réunions et notes** : source n° 1 de l'agent PV ;
- **05 Ateliers et outils** ;
- **06 Livrables et capitalisation** : candidats à la part membres ou publique ;
- la feuille Google Sheets **« Suivi de mission #… »** sert de pont lisible entre le Drive et le Pilote.

Le préfixe sert de **statut**, lu par les agents : « En cours » correspond à « active ». Je propose d'ajouter « En veille » et « Clôturée », alignés sur les statuts déjà présents dans le 3/3. Chaque sous-dossier porte par défaut un **niveau d'étiquette**, ce qui facilite le travail des agents.

### 8.2 La logique fractale

Chaque mission a un agent qui calcule l'avancement, les décisions, les questions en suspens, le temps passé par rapport au budget et les livrables. Il écrit **une ligne de synthèse étiquetée**, et cette ligne remonte :
- vers le **Pilote des accompagnants**, qui reçoit la synthèse complète au niveau « membres », plus les alertes de temps ;
- vers le **Pilote 3/3**, qui reçoit la synthèse et ce qui touche la coordination : facturation, arbitrages, ordre du jour de l'hebdo ;
- vers le **tableau OA**, qui ne reçoit que des chiffres agrégés.

La remontée **recopie un résumé, jamais le document**, et l'information garde son étiquette d'origine : ce qui est « interne » ne monte jamais vers un niveau plus ouvert.

### 8.3 Le Pilote du réseau d'accompagnants

C'est une copie de la recette 3/3 (en-tête, onglets, journal ouvert en premier, salle d'attente) centrée sur **la liste des missions en cours**. Chaque carte de mission affiche le statut, le territoire, le référent, les rôles, une jauge de temps (verte, orange, rouge), les décisions récentes, les questions en suspens, les liens vers le dossier Drive et vers la quête CTG.

**Une mission = une quête** : au passage en « En cours », un agent crée la quête en brouillon avec la part publique et stocke son identifiant dans la fiche. Les mises à jour suivantes demandent un outil de modification de quête qui **n'existe pas encore** côté CTG (voir la section 6).

### 8.4 Le schéma d'étiquettes

Chaque information captée (note, décision, question, tâche, temps, livrable) reçoit à la source :

| Étiquette | Valeurs | Exemple |
|---|---|---|
| `mission_id` | identifiant court, aussi utilisé dans le nom du Sheet | `palace-la-louviere` |
| `nature` | `support` · `mission` · `gt` | `mission` |
| `niveau` | `interne` · `mission` (accompagnants actifs sur la mission) · `membres` · `public` | `mission` |
| `territoire` | commune ou région | `La Louvière` |
| `personnes` | liste de {personne, rôle} ; rôles : `prestation`, `apport`, `suivi_client`, `coordination` | `{eve, prestation}` |
| `type` | `tâche` · `décision` · `question` · `temps` · `livrable` · `info` | `décision` |
| `statut` | `proposé` (par un agent) · `validé` · `publié` · `retiré` | `proposé` |
| `source` | `pv` · `mail` · `drive` · `whatsapp` · `element` · `zoom` · `manuel`, avec le lien et la date | `pv, 12/11` |
| `consentement` | `ok` · `à demander` · `refusé` | `ok` |

Règle par défaut : **en cas de doute, l'agent choisit le niveau le plus fermé**. Seul un humain peut ouvrir un niveau.

**Qui voit quoi :**

| Niveau | Pilote de mission | Pilote des accompagnants | Pilote 3/3 | Tableau OA | Quête CTG publique |
|---|---|---|---|---|---|
| interne (contrat, facturation, tensions) | équipe 3/3 et référent | non, seulement un indicateur | oui | non | non |
| mission | accompagnants actifs sur la mission | synthèse seule | synthèse | non | non |
| membres | oui | oui | oui | chiffres | non |
| public | oui | oui | oui | oui | **titre, résumé, personnes, structures**, après validation |

### 8.5 Le risque du dossier Drive largement partagé

Le dossier Palace est partagé avec **une quarantaine de personnes, dont des externes**. Le Drive applique ses propres permissions, et un classement dans le Pilote **ne protège rien** si le document est lisible dans le dossier. Conséquences :
- **02 Offre, contrat et facturation** et toute note « interne » ne doivent pas se trouver dans un dossier partagé avec des externes. Il faut un sous-dossier ou un dossier parallèle « interne » avec des droits restreints, **ou** retirer les externes de la racine et ne partager avec eux que 03, 05 et 06 ;
- les **sorties des agents** (synthèses, Sheet de suivi) héritent du partage du dossier où elles sont écrites. Il ne faut **jamais écrire une synthèse interne dans un dossier ouvert** ;
- il faut **un contrôle régulier des permissions** (le connecteur Drive permet de les lire). Un agent compare le niveau attendu du dossier à ses permissions réelles et signale les écarts dans la salle d'attente, **sans rien modifier lui-même**.

## 9. Décisions à soumettre à PA

1. **Socle technique du cockpit.**
   - (a) Artefacts Claude copiés depuis une recette 3/3 nettoyée : rapide, mais étanchéité limitée au partage de chaque artefact.
   - (b) CTG comme base de vérité pour les missions, les Pilotes-artefacts n'étant que des vues : solide, mais il faut développer côté CTG.
   - (c) Hybride : artefacts pour l'interne, CTG pour les parts membres et publique.
2. **Groupes de travail** : un Pilote unique, un par groupe, ou unique puis séparation à la demande (options A, B, C de la section 4).
3. **Modèle d'étiquettes** : valider les quatre niveaux, dont la création d'un niveau « mission » distinct de « membres », et la règle « en cas de doute, le plus fermé ».
4. **Partage Drive** : restructurer les dossiers de mission (séparer l'interne) avant toute captation, ou limiter d'abord la captation aux sous-dossiers ouverts.
5. **WhatsApp et Zoom** : les garder hors du périmètre au démarrage, ou les inclure avec un consentement explicite des groupes.
6. **Évolutions CTG à commander** : modifier et clôturer une quête, champ d'identifiant externe, création de décisions et de questions, rôles et temps.
7. **Garde-fou de temps** : unité (heures ou demi-journées, le Configurateur raisonnant en demi-journées de 4 h) et seuil de l'alerte rouge.

**Risques** : fuite par le partage Drive ; identité seulement déclarative dans les Pilotes ; dépendance à un seul compte et à un Mac allumé ; captation de personnes externes sans consentement ; divergence des copies de Pilotes ; clé d'écriture CTG exposée si elle est mise dans une page.

**Accès manquants** : le Cadre de coordination des missions (illisible, erreur réseau) ; le pilote de mission de La Louvière (introuvable) ; le dossier Drive Palace et son Sheet (non consultés) ; le schéma complet des quêtes CTG (seules les migrations ont été survolées) ; l'existence d'une clé de guilde Trois-Tiers.

---

## Annexe technique

- **Pilote 3/3** : environ 217 Ko, contrat 0.2.96. Capacités : db, downloads, sample, mcp (Google Drive `read_file_content` ; Claude Code Remote `list_triggers`, `fire_trigger`). Collections : `tasks`, `missions`, `journal`, `proposals`, `absences`, `hebdo_points`, `days`, `meta/*` (config, états des agents). Champs modifiables d'une tâche : `title, status, start, end, pilot, contributors, milestone, estimate_h, notes_append, subtasks_add, deps, mission`. Mission : `name, type (marche-public|autre), lieu, statut (active|veille|cloturee), referent, aliases, context_md, requests_md, next_actions, sources[]`. Préférences locales (localStorage `p33:*`).
- **Pivot** : capacité db ; collection `state` en surcouche des tâches écrites dans le code (`LANES`).
- **Poiethic** : capacité db ; collection `tasks` (`laneId, title, start, end, ms, territoire, responsables, statut, subtasks, notes`).
- **Configurateur AMO** : capacité sample seulement ; `MODULES` (rule(f) → rec/opt/na, min/max en demi-journées, tier amorce/second/post), `PACKS`, `SCENARIOS`, taux de 400 € (340 € pour les petits moyens), coefficient de 1,15.
- **CTG** : `src/lib/mcp/index.ts` (OAuth via Supabase, 8 outils personnels) ; `supabase/functions/guild-mcp/index.ts` (clé `ctg_…` hachée dans `guild_mcp_tokens`, scopes read/write, 25 outils dont `create_quest` (is_draft par défaut à true), `create_subtask`, `update_subtask_status`, `attach_link`, `list_decisions`, `vote_on_decision`, `log_contribution`, `create_event`) ; `guild-mcp-tokens` (création de clés réservée aux administrateurs de guilde). Aucun `update_quest` ni `external_id` trouvé dans guild-mcp. `quests.universe_visibility` (défaut `both`) existe ; son rôle n'a pas été vérifié.
