# --- Stage 1: compile the API with the full .NET SDK ---
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY HelloApi.csproj .
RUN dotnet restore
COPY . .
RUN dotnet publish -c Release -o /app --no-restore

# --- Stage 2: small runtime-only image ---
FROM mcr.microsoft.com/dotnet/aspnet:10.0
ARG APP_VERSION=dev
ENV APP_VERSION=$APP_VERSION
WORKDIR /app
COPY --from=build /app .
# Run as the image's built-in non-root user. ASP.NET listens on port 8080 by default.
USER $APP_UID
EXPOSE 8080
ENTRYPOINT ["dotnet", "HelloApi.dll"]
