#!/usr/bin/env bash
### ci_supabase_start.sh – Den lokalen Supabase-Stack in CI starten, robust
### gegen Drosselung der Image-Registries. Genutzt vom Schema Dry Run
### (ci.yml). Übernommen aus PilzBuddy (dort aus FWApp), angepasst an die
### Dienste, die TrailBuddy braucht.
###
### Drei Dinge, jedes mit Grund:
###
### 1. Die Registry-Vorgabe der Action wird aufgehoben. `supabase/setup-cli`
###    setzt SUPABASE_INTERNAL_IMAGE_REGISTRY=ghcr.io — und eine gesetzte
###    Registry schaltet die Ausweichkette der CLI ab (public.ecr.aws →
###    ghcr.io → Docker Hub). Am 2026-09-23 drosselte ghcr.io die Runner
###    („toomanyrequests"): PilzBuddys Schema Dry Run scheiterte viermal
###    hintereinander am Start des Stacks, ohne dass ein Test lief.
### 2. Nur die Dienste, die der Dry Run braucht — weniger Images heißt
###    weniger Downloads, die gedrosselt werden können. `config.toml`
###    schaltet Studio, Realtime, Analytics und den Pooler schon ab; hier
###    fallen zusätzlich weg:
###      - imgproxy       (Bildumwandlung, nutzt kein Test)
###      - postgres-meta  (nur für Studio)
###      - vector         (Log-Sammler)
###      - edge-runtime   (push_flush_check.sh schickt absichtlich an
###                        eine Adresse, die ins Leere zeigt — die
###                        Function selbst wird im Dry Run nie gerufen)
###    Es BLEIBEN: db (mit PostGIS), kong, gotrue, postgrest, mailpit
###    (`auth_reset_check.sh` liest dort die Codes) und seit Patch 026
###    storage-api (Bucket der Hinweis-Fotos; `photo_access_check.sh`
###    prüft seine Policies).
###    ⚠️ `-x` will die IMAGE-Namen. Die Namen aus `supabase start --help`
###    nimmt die CLI stillschweigend an und startet die Dienste trotzdem
###    (in FWApp mit `docker ps` nachgesehen).
### 3. Drei Versuche mit wachsender Pause. Eine Drosselung ist
###    vorübergehend.
set -euo pipefail

unset SUPABASE_INTERNAL_IMAGE_REGISTRY

for versuch in 1 2 3; do
  if supabase start -x imgproxy,postgres-meta,vector,edge-runtime,logflare,realtime,studio; then
    exit 0
  fi
  echo "::warning::supabase start scheiterte (Versuch $versuch/3) — neuer Versuch in $((versuch * 30)) s"
  supabase stop --no-backup || true
  sleep $((versuch * 30))
done
echo "::error::supabase start scheiterte dreimal"
exit 1
