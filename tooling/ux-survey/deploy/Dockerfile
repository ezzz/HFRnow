# Construction en deux étapes ; image finale sans shell, en utilisateur non root.
# Contexte de construction : tooling/ux-survey/ (docker compose build, voir compose.yaml).
FROM golang:1.27.3 AS construction
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
# Architecture de l'hôte : TARGETARCH est fourni par BuildKit.
ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} go build -trimpath -ldflags="-s -w" -o /ux-survey ./cmd/ux-survey

FROM gcr.io/distroless/static:nonroot
COPY --from=construction /ux-survey /ux-survey
USER 65532:65532
ENTRYPOINT ["/ux-survey"]
CMD ["serve"]
