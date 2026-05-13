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
    "Config summary: Topstep={Topstep}, TopstepReadOnly={TopstepReadOnly}, Chart={Chart}, Jwt={Jwt}, TemporalNamespace={TemporalNamespace}, TemporalApiKey={TemporalApiKey}, MarketDataApiBaseUrl={MarketDataApiBaseUrl}, MarketDataApiKey={MarketDataApiKey}, StrapiBaseUrl={StrapiBaseUrl}, StrapiToken={StrapiToken}, DefaultLogLevel={DefaultLogLevel}, AllowAnonymousRegistration={AllowAnonymousRegistration}, EnableHubspotEmails={EnableHubspotEmails}, ImmediateEnforcementThreshold={ImmediateEnforcementThreshold}",
    startupSnapshot.TopstepConnectionPresent ? "present" : "missing",
    startupSnapshot.TopstepReadOnlyConnectionPresent ? "present" : "missing",
    startupSnapshot.ChartConnectionPresent ? "present" : "missing",
    startupSnapshot.JwtSecretPresent ? "present" : "missing",
    startupSnapshot.TemporalNamespace ?? "missing",
    startupSnapshot.TemporalApiKeyPresent ? "present" : "missing",
    startupSnapshot.MarketDataApiBaseUrl ?? "missing",
    startupSnapshot.MarketDataApiKeyPresent ? "present" : "missing",
    startupSnapshot.StrapiBaseUrl ?? "missing",
    startupSnapshot.StrapiTokenPresent ? "present" : "missing",
    startupSnapshot.DefaultLogLevel ?? "missing",
    startupSnapshot.AllowAnonymousRegistration,
    startupSnapshot.EnableHubspotEmails,
    startupSnapshot.ImmediateEnforcementThreshold);

app.MapGet("/", () => Results.Redirect("/config-check"));
app.MapGet("/healthz", () => Results.Ok(new { status = "ok" }));
app.MapGet("/config-check", (IConfiguration configuration) => Results.Ok(BuildSnapshot(configuration)));

app.Run();

static ConfigSnapshot BuildSnapshot(IConfiguration configuration)
{
    var topstepConnection = configuration.GetConnectionString("Topstep");
    var topstepReadOnlyConnection = configuration.GetConnectionString("TopstepReadOnly");
    var chartConnection = configuration.GetConnectionString("Chart");
    var jwtSecret = configuration["Jwt:Secret"];
    var temporalApiKey = configuration["Temporal:ApiKey"];
    var marketDataApiKey = configuration["MarketDataApi:ApiKey"];
    var strapiToken = configuration["Strapi:Token"];

    return new ConfigSnapshot(
        TopstepConnectionPresent: !string.IsNullOrWhiteSpace(topstepConnection),
        TopstepConnectionPreview: MaskConnectionString(topstepConnection),
        TopstepReadOnlyConnectionPresent: !string.IsNullOrWhiteSpace(topstepReadOnlyConnection),
        TopstepReadOnlyConnectionPreview: MaskConnectionString(topstepReadOnlyConnection),
        ChartConnectionPresent: !string.IsNullOrWhiteSpace(chartConnection),
        ChartConnectionPreview: MaskConnectionString(chartConnection),
        JwtSecretPresent: !string.IsNullOrWhiteSpace(jwtSecret),
        TemporalApiKeyPresent: !string.IsNullOrWhiteSpace(temporalApiKey),
        TemporalNamespace: configuration["Temporal:Namespace"],
        TemporalTaskQueues: configuration.GetSection("Temporal:TaskQueues").Get<string[]>() ?? [],
        MarketDataApiBaseUrl: configuration["MarketDataApi:BaseUrl"],
        MarketDataApiKeyPresent: !string.IsNullOrWhiteSpace(marketDataApiKey),
        StrapiBaseUrl: configuration["Strapi:BaseUrl"],
        StrapiTokenPresent: !string.IsNullOrWhiteSpace(strapiToken),
        DefaultLogLevel: configuration["Logging:LogLevel:Default"],
        AllowAnonymousRegistration: configuration.GetValue<bool?>("FeatureFlags:AllowAnonymousRegistration"),
        EnableHubspotEmails: configuration.GetValue<bool?>("FeatureFlags:EnableHubspotEmails"),
        ImmediateEnforcementThreshold: configuration.GetValue<int>("HedgeDetection:ImmediateEnforcementThreshold"),
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
    bool TopstepConnectionPresent,
    string? TopstepConnectionPreview,
    bool TopstepReadOnlyConnectionPresent,
    string? TopstepReadOnlyConnectionPreview,
    bool ChartConnectionPresent,
    string? ChartConnectionPreview,
    bool JwtSecretPresent,
    bool TemporalApiKeyPresent,
    string? TemporalNamespace,
    string[] TemporalTaskQueues,
    string? MarketDataApiBaseUrl,
    bool MarketDataApiKeyPresent,
    string? StrapiBaseUrl,
    bool StrapiTokenPresent,
    string? DefaultLogLevel,
    bool? AllowAnonymousRegistration,
    bool? EnableHubspotEmails,
    int ImmediateEnforcementThreshold,
    string? EnvironmentName,
    string? SecretSource);
