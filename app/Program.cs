using Microsoft.Extensions.Configuration;

var builder = WebApplication.CreateBuilder(args);

builder.Configuration.Sources.Clear();
builder.Configuration
    .AddJsonFile("appsettings.json", optional: false)
    .AddJsonFile("appsettings.global.json", optional: true)
    .AddJsonFile("secrets/appsettings.secrets.json", optional: true)
    .AddEnvironmentVariables();

var app = builder.Build();

var startupSnapshot = BuildSnapshot(app.Configuration);
app.Logger.LogInformation(
    "Config summary: TopStep={TopStep}, Chart={Chart}, Jwt={Jwt}, MarketDataBaseUrl={MarketDataBaseUrl}, DefaultLogLevel={DefaultLogLevel}",
    startupSnapshot.TopStepConnectionPresent ? "present" : "missing",
    startupSnapshot.ChartConnectionPresent ? "present" : "missing",
    startupSnapshot.JwtSecretPresent ? "present" : "missing",
    startupSnapshot.MarketDataBaseUrl ?? "missing",
    startupSnapshot.DefaultLogLevel ?? "missing");

app.MapGet("/", () => Results.Redirect("/config-check"));
app.MapGet("/healthz", () => Results.Ok(new { status = "ok" }));
app.MapGet("/config-check", (IConfiguration configuration) => Results.Ok(BuildSnapshot(configuration)));

app.Run();

static ConfigSnapshot BuildSnapshot(IConfiguration configuration)
{
    var topStepConnection = configuration.GetConnectionString("TopStep");
    var chartConnection = configuration.GetConnectionString("Chart");
    var jwtSecret = configuration["Jwt:Secret"];

    return new ConfigSnapshot(
        TopStepConnectionPresent: !string.IsNullOrWhiteSpace(topStepConnection),
        TopStepConnectionPreview: MaskConnectionString(topStepConnection),
        ChartConnectionPresent: !string.IsNullOrWhiteSpace(chartConnection),
        ChartConnectionPreview: MaskConnectionString(chartConnection),
        JwtSecretPresent: !string.IsNullOrWhiteSpace(jwtSecret),
        DefaultLogLevel: configuration["Logging:LogLevel:Default"],
        MarketDataBaseUrl: configuration["Dependencies:MarketDataBaseUrl"],
        EnvironmentName: configuration["Demo:EnvironmentName"],
        SecretSource: configuration["Demo:SecretSource"]);
}

static string? MaskConnectionString(string? connectionString)
{
    if (string.IsNullOrWhiteSpace(connectionString))
        return null;

    var segments = connectionString
        .Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
        .Select(segment =>
        {
            if (segment.StartsWith("Password=", StringComparison.OrdinalIgnoreCase))
                return "Password=***";

            return segment;
        });

    return string.Join(';', segments);
}

internal sealed record ConfigSnapshot(
    bool TopStepConnectionPresent,
    string? TopStepConnectionPreview,
    bool ChartConnectionPresent,
    string? ChartConnectionPreview,
    bool JwtSecretPresent,
    string? DefaultLogLevel,
    string? MarketDataBaseUrl,
    string? EnvironmentName,
    string? SecretSource);

