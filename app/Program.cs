using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Options;
using Npgsql;

var builder = WebApplication.CreateBuilder(args);

builder.Configuration.Sources.Clear();
builder.Configuration
    .AddJsonFile("appsettings.json", optional: false)
    .AddJsonFile("appsettings.global.json", optional: true)
    .AddKeyPerFile(directoryPath: "/app/secrets", optional: true, reloadOnChange: false)
    .AddEnvironmentVariables();

foreach (var name in new[] { "Topstep", "TopstepReadOnly", "Chart" })
{
    builder.Services.AddOptions<NpgsqlConnectionStringBuilder>(name)
        .Bind(builder.Configuration.GetSection($"ConnectionStrings:{name}"))
        .Validate(b => !string.IsNullOrWhiteSpace(b.Host), $"ConnectionStrings:{name}:Host is required")
        .Validate(b => !string.IsNullOrWhiteSpace(b.Username), $"ConnectionStrings:{name}:Username is required")
        .Validate(b => !string.IsNullOrWhiteSpace(b.Password), $"ConnectionStrings:{name}:Password is required")
        .Validate(b => !string.IsNullOrWhiteSpace(b.Database), $"ConnectionStrings:{name}:Database is required")
        .ValidateOnStart();
}

var app = builder.Build();

var connections = app.Services.GetRequiredService<IOptionsMonitor<NpgsqlConnectionStringBuilder>>();

var startupSnapshot = BuildSnapshot(app.Configuration, connections);
app.Logger.LogInformation(
    "Config summary: Topstep={Topstep}, TopstepReadOnly={TopstepReadOnly}, Chart={Chart}, Jwt={Jwt}, TemporalNamespace={TemporalNamespace}, TemporalApiKey={TemporalApiKey}, MarketDataApiBaseUrl={MarketDataApiBaseUrl}, MarketDataApiKey={MarketDataApiKey}, StrapiBaseUrl={StrapiBaseUrl}, StrapiToken={StrapiToken}, StripeApiKey={StripeApiKey}, ElasticSearchUrl={ElasticSearchUrl}, ElasticSearchPassword={ElasticSearchPassword}, ElasticSearchCloudApiKey={ElasticSearchCloudApiKey}, DefaultLogLevel={DefaultLogLevel}, AllowAnonymousRegistration={AllowAnonymousRegistration}, EnableHubspotEmails={EnableHubspotEmails}, ImmediateEnforcementThreshold={ImmediateEnforcementThreshold}",
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
    startupSnapshot.StripeApiKeyPresent ? "present" : "missing",
    startupSnapshot.ElasticSearchUrl ?? "missing",
    startupSnapshot.ElasticSearchPasswordPresent ? "present" : "missing",
    startupSnapshot.ElasticSearchCloudApiKeyPresent ? "present" : "missing",
    startupSnapshot.DefaultLogLevel ?? "missing",
    startupSnapshot.AllowAnonymousRegistration,
    startupSnapshot.EnableHubspotEmails,
    startupSnapshot.ImmediateEnforcementThreshold);

app.MapGet("/", () => Results.Redirect("/config-check"));
app.MapGet("/healthz", () => Results.Ok(new { status = "ok" }));
app.MapGet("/config-check", (IConfiguration configuration, IOptionsMonitor<NpgsqlConnectionStringBuilder> connections) =>
    Results.Ok(BuildSnapshot(configuration, connections)));

app.Run();

static ConfigSnapshot BuildSnapshot(IConfiguration configuration, IOptionsMonitor<NpgsqlConnectionStringBuilder> connections)
{
    var topstep = connections.Get("Topstep");
    var topstepReadOnly = connections.Get("TopstepReadOnly");
    var chart = connections.Get("Chart");
    var jwtSecret = configuration["Jwt:Secret"];
    var temporalApiKey = configuration["Temporal:ApiKey"];
    var marketDataApiKey = configuration["MarketDataApi:ApiKey"];
    var strapiToken = configuration["Strapi:Token"];
    var stripeApiKey = configuration["Stripe:ApiKey"];
    var elasticSearchPassword = configuration["ElasticSearch:Password"];
    var elasticSearchCloudApiKey = configuration["ElasticSearch:CloudApiKey"];

    return new ConfigSnapshot(
        TopstepConnectionPresent: !string.IsNullOrWhiteSpace(topstep.Host),
        TopstepConnectionPreview: MaskConnectionString(topstep),
        TopstepReadOnlyConnectionPresent: !string.IsNullOrWhiteSpace(topstepReadOnly.Host),
        TopstepReadOnlyConnectionPreview: MaskConnectionString(topstepReadOnly),
        ChartConnectionPresent: !string.IsNullOrWhiteSpace(chart.Host),
        ChartConnectionPreview: MaskConnectionString(chart),
        JwtSecretPresent: !string.IsNullOrWhiteSpace(jwtSecret),
        TemporalApiKeyPresent: !string.IsNullOrWhiteSpace(temporalApiKey),
        TemporalNamespace: configuration["Temporal:Namespace"],
        TemporalTaskQueues: configuration.GetSection("Temporal:TaskQueues").Get<string[]>() ?? [],
        MarketDataApiBaseUrl: configuration["MarketDataApi:BaseUrl"],
        MarketDataApiKeyPresent: !string.IsNullOrWhiteSpace(marketDataApiKey),
        StrapiBaseUrl: configuration["Strapi:BaseUrl"],
        StrapiTokenPresent: !string.IsNullOrWhiteSpace(strapiToken),
        StripeApiKeyPresent: !string.IsNullOrWhiteSpace(stripeApiKey),
        ElasticSearchUrl: configuration["ElasticSearch:Url"],
        ElasticSearchPasswordPresent: !string.IsNullOrWhiteSpace(elasticSearchPassword),
        ElasticSearchCloudApiKeyPresent: !string.IsNullOrWhiteSpace(elasticSearchCloudApiKey),
        DefaultLogLevel: configuration["Logging:LogLevel:Default"],
        AllowAnonymousRegistration: configuration.GetValue<bool?>("FeatureFlags:AllowAnonymousRegistration"),
        EnableHubspotEmails: configuration.GetValue<bool?>("FeatureFlags:EnableHubspotEmails"),
        ImmediateEnforcementThreshold: configuration.GetValue<int>("HedgeDetection:ImmediateEnforcementThreshold"),
        EnvironmentName: configuration["Demo:EnvironmentName"],
        SecretSource: configuration["Demo:SecretSource"]);
}

static string? MaskConnectionString(NpgsqlConnectionStringBuilder builder)
{
    if (string.IsNullOrWhiteSpace(builder.Host))
        return null;

    var masked = new NpgsqlConnectionStringBuilder(builder.ConnectionString);
    if (!string.IsNullOrWhiteSpace(masked.Password))
        masked.Password = "***";
    return masked.ConnectionString;
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
    bool StripeApiKeyPresent,
    string? ElasticSearchUrl,
    bool ElasticSearchPasswordPresent,
    bool ElasticSearchCloudApiKeyPresent,
    string? DefaultLogLevel,
    bool? AllowAnonymousRegistration,
    bool? EnableHubspotEmails,
    int ImmediateEnforcementThreshold,
    string? EnvironmentName,
    string? SecretSource);
