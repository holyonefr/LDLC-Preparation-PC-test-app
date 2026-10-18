# Réponse officielle enregistrée pour l'audit

`gigabyte-official-2026-10-18.html` est la réponse HTTP 200 du 18 octobre 2026 à
`https://www.gigabyte.com/Ajax/SupportFunction/GetUtilityAjax?ClassGroup=2&Page=1&KeyWord=GIGABYTE%20Control%20Center`.
La détection réelle dans le cloud a sélectionné GCC 26.09.10.01.
Les fins de ligne et espaces de fin sont normalisés pour le stockage Git ; le
contenu des liens n'est pas modifié. L'empreinte d'audit concerne ce fichier conservé.

Le runner Windows reçoit HTTP 403 sur cette consultation. Le paramètre explicite
`-RecordedOfficialCatalogue` permet uniquement un audit statique du téléchargement
annoncé dans cette réponse enregistrée. Son JSON indique `recorded_response` et
l'empreinte de la capture ; il ne valide pas la disponibilité du catalogue actuel
depuis Windows et n'est jamais utilisé comme repli par l'application.
