# Construction en deux étapes ; image finale sans shell, en utilisateur non root.
# Contexte de construction : tooling/ux-survey/ (docker compose build, voir compose.yaml).
# Images de base épinglées par condensat (index multi-architecture) : le tag seul peut changer sous nos pieds (F4).
# Pour mettre à jour : docker buildx imagetools inspect <image:tag>, relever « Digest », relancer le CI.
FROM golang:1.27.4@sha256:205c7636d74e0ffbe3d007162df7d74f859f5a8c8322dfb9f907977686c126cf AS construction
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
# Architecture de l'hôte : TARGETARCH est fourni par BuildKit.
ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} go build -trimpath -ldflags="-s -w" -o /ux-survey ./cmd/ux-survey

FROM gcr.io/distroless/static:nonroot@sha256:aafe993665bf6200db38a02c11a9351e782a84b6a45e7f33b6695638c88e3931
COPY --from=construction /ux-survey /ux-survey
USER 65532:65532
# Pas de shell ni de curl dans l'image : la sonde est le binaire lui-même (GET /healthz, sans accès à la base).
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD ["/ux-survey", "sante"]
ENTRYPOINT ["/ux-survey"]
CMD ["serve"]
