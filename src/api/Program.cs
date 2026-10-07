var builder = WebApplication.CreateBuilder(args);
builder.Services.AddHealthChecks();

var app = builder.Build();

// In Kubernetes these come from environment variables (ConfigMap "api-config").
// APP_VERSION is baked into the image at build time (see Dockerfile).
var greeting = app.Configuration["GREETING"] ?? "Hello from .NET";
var environmentName = app.Configuration["APP_ENVIRONMENT"] ?? "development";
var version = app.Configuration["APP_VERSION"] ?? "dev";

app.MapGet("/api/hello", () => Results.Ok(new
{
    message = greeting,
    environment = environmentName,
    version,
    hostname = Environment.MachineName, // the pod name when running in Kubernetes
    timeUtc = DateTime.UtcNow
}));

// Liveness: "is the process alive?"  Readiness: "can it take traffic right now?"
// This tiny API has no dependencies, so both just report Healthy.
app.MapHealthChecks("/healthz/live");
app.MapHealthChecks("/healthz/ready");

app.Run();
