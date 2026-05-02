using System.Net;
using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.Model;
using Amazon.Runtime;
using Docker.DotNet;
using Docker.DotNet.Models;

namespace DockerConnectivity.Tests;

/// <summary>
/// Starts a named DynamoDB Local container using port binding, following the LocalDbFixture pattern:
/// dynamic port allocation with retry on collision, health-check via ListTablesAsync,
/// and a CreateConfiguration() helper that exposes DYNAMO_PORT for the system under test.
/// </summary>
[Trait("Category", "Integration")]
public class DynamoDbConnectivityTests : IAsyncLifetime
{
    private const string ImageName = "amazon/dynamodb-local";
    private const string ImageTag = "3.0.0";
    private const int DefaultDynamoDbPort = 8000;

    private static readonly TimeSpan WarmUpTimeout = TimeSpan.FromSeconds(30);
    private static readonly TimeSpan WarmUpInterval = TimeSpan.FromSeconds(2);

    private string _sandboxNetworkName = null!;

    private DockerClient _docker = null!;
    private string _containerName = null!;
    private string _containerHost = null!;

    // ---------------------------------------------------------------------------
    // IAsyncLifetime
    // ---------------------------------------------------------------------------

    public async Task InitializeAsync()
    {
        if (!File.Exists("/var/run/docker.sock"))
            return;

        _docker = new DockerClientConfiguration().CreateClient();
        await CreateImageAsync(ImageName, ImageTag);

        _containerName = GenerateContainerName();
        _sandboxNetworkName = await DetectSandboxNetworkAsync();

        await RemoveExistingDynamoDbContainersAsync();
        _containerHost = await CreateAndStartContainerAsync();
        await WaitHealthConnectionAsync(WarmUpTimeout, WarmUpInterval);
    }

    public async Task DisposeAsync()
    {
        if (_docker is null)
            return;

        await StopContainerLenientAsync(_containerName);
        _docker.Dispose();
    }

    // ---------------------------------------------------------------------------
    // Configuration - exposes DYNAMO_PORT for the system under test
    // ---------------------------------------------------------------------------

    public AmazonDynamoDBConfig CreateConfiguration() => new()
    {
        ServiceURL = $"http://{_containerHost}:{DefaultDynamoDbPort}",
        Timeout = TimeSpan.FromSeconds(5),
        MaxErrorRetry = 1,
        UseHttp = true,
        AuthenticationRegion = "us-east-1",
    };

    private AmazonDynamoDBClient CreateClient() =>
        new(new BasicAWSCredentials("fake", "fake"), CreateConfiguration());

    // ---------------------------------------------------------------------------
    // Tests
    // ---------------------------------------------------------------------------

    [DockerSocketFact]
    public async Task ListTables_OnFreshInstance_ReturnsEmptyList()
    {
        using var client = CreateClient();

        var response = await client.ListTablesAsync();

        Assert.Equal(HttpStatusCode.OK, response.HttpStatusCode);
        Assert.Empty(response.TableNames);
    }

    [DockerSocketFact]
    public async Task CreateTable_ThenListTables_ReturnsTableName()
    {
        using var client = CreateClient();
        const string tableName = "TestTable";

        await client.CreateTableAsync(new CreateTableRequest
        {
            TableName = tableName,
            KeySchema = [new KeySchemaElement("pk", KeyType.HASH)],
            AttributeDefinitions = [new AttributeDefinition("pk", ScalarAttributeType.S)],
            BillingMode = BillingMode.PAY_PER_REQUEST,
        });

        var list = await client.ListTablesAsync();
        Assert.Contains(tableName, list.TableNames);
    }

    [DockerSocketFact]
    public async Task PutItem_ThenGetItem_RoundTrips()
    {
        using var client = CreateClient();
        const string tableName = "RoundTripTable";

        await client.CreateTableAsync(new CreateTableRequest
        {
            TableName = tableName,
            KeySchema = [new KeySchemaElement("pk", KeyType.HASH)],
            AttributeDefinitions = [new AttributeDefinition("pk", ScalarAttributeType.S)],
            BillingMode = BillingMode.PAY_PER_REQUEST,
        });

        await client.PutItemAsync(tableName, new Dictionary<string, AttributeValue>
        {
            ["pk"] = new AttributeValue("item-1"),
            ["value"] = new AttributeValue("hello"),
        });

        var result = await client.GetItemAsync(tableName, new Dictionary<string, AttributeValue>
        {
            ["pk"] = new AttributeValue("item-1"),
        });

        Assert.True(result.IsItemSet);
        Assert.Equal("hello", result.Item["value"].S);
    }

    // ---------------------------------------------------------------------------
    // Docker helpers
    // ---------------------------------------------------------------------------

    private async Task RemoveExistingDynamoDbContainersAsync()
    {
        var containers = await _docker.Containers.ListContainersAsync(
            new ContainersListParameters { All = true });

        var dynamoContainers = containers.Where(c =>
            c.Image.StartsWith("amazon/dynamodb-local", StringComparison.OrdinalIgnoreCase));

        foreach (var container in dynamoContainers)
        {
            try
            {
                await _docker.Containers.StopContainerAsync(
                    container.ID, new ContainerStopParameters { WaitBeforeKillSeconds = 3 });
                await _docker.Containers.RemoveContainerAsync(
                    container.ID, new ContainerRemoveParameters { Force = true });
            }
            catch { /* best-effort */ }
        }
    }

    private async Task CreateImageAsync(string imageName, string imageTag)
    {
        IProgress<JSONMessage> progress = new Progress<JSONMessage>();
        await _docker.Images.CreateImageAsync(
            new ImagesCreateParameters { FromImage = imageName, Tag = imageTag },
            authConfig: null,
            progress);
    }

    private async Task<string> DetectSandboxNetworkAsync()
    {
        // /etc/hostname contains the short container ID of the current container.
        string selfId = (await File.ReadAllTextAsync("/etc/hostname")).Trim();
        var self = await _docker.Containers.InspectContainerAsync(selfId);
        // Prefer a non-default-bridge network (compose networks are named, e.g. sandbox_default).
        return self.NetworkSettings.Networks.Keys
            .FirstOrDefault(n => n != "bridge")
            ?? self.NetworkSettings.Networks.Keys.First();
    }

    private async Task<string> CreateAndStartContainerAsync()
    {
        var response = await _docker.Containers.CreateContainerAsync(new CreateContainerParameters
        {
            Image = $"{ImageName}:{ImageTag}",
            Name = _containerName,
            // Run with -inMemory so no disk I/O is required.
            Cmd = ["-jar", "DynamoDBLocal.jar", "-inMemory"],
            // Join the sandbox's compose network so inter-container HTTP is routable.
            NetworkingConfig = new Docker.DotNet.Models.NetworkingConfig
            {
                EndpointsConfig = new Dictionary<string, Docker.DotNet.Models.EndpointSettings>
                {
                    [_sandboxNetworkName] = new Docker.DotNet.Models.EndpointSettings()
                }
            },
        });

        bool started = await _docker.Containers.StartContainerAsync(
            response.ID, new ContainerStartParameters());

        if (!started)
            throw new InvalidOperationException($"Failed to start DynamoDB container '{_containerName}'.");

        // Inspect to get the IP on the shared compose network.
        var inspect = await _docker.Containers.InspectContainerAsync(response.ID);
        string ip = (inspect.NetworkSettings.Networks.TryGetValue(_sandboxNetworkName, out var netInfo)
                        ? netInfo.IPAddress
                        : null)
            ?? inspect.NetworkSettings.Networks.Values
                .Select(n => n.IPAddress)
                .FirstOrDefault(a => !string.IsNullOrEmpty(a))
            ?? throw new InvalidOperationException($"Could not determine IP for container '{_containerName}'.");

        return ip;
    }

    private async Task StopContainerLenientAsync(string containerName)
    {
        try
        {
            var containers = await _docker.Containers.ListContainersAsync(
                new ContainersListParameters { All = true });

            var container = containers.FirstOrDefault(c => c.Names.Contains($"/{containerName}"));
            if (container is null)
                return;

            await _docker.Containers.StopContainerAsync(
                container.ID, new ContainerStopParameters { WaitBeforeKillSeconds = 3 });
            await _docker.Containers.RemoveContainerAsync(
                container.ID, new ContainerRemoveParameters { Force = true });
        }
        catch { /* best-effort cleanup */ }
    }

    private async Task WaitHealthConnectionAsync(TimeSpan timeout, TimeSpan interval)
    {
        var start = DateTime.UtcNow;
        Exception? last = null;

        while (DateTime.UtcNow - start < timeout)
        {
            try
            {
                using var client = new AmazonDynamoDBClient(
                    new BasicAWSCredentials("fake", "fake"), CreateConfiguration());
                await client.ListTablesAsync();
                return;
            }
            catch (Exception ex)
            {
                last = ex;
                await Task.Delay(interval);
            }
        }

        throw new TimeoutException(
            $"Could not connect to DynamoDB Local at {_containerHost}:{DefaultDynamoDbPort} within {timeout.TotalSeconds}s.", last);
    }

    private static string GenerateContainerName() =>
        $"dynamodb-local-test-{Guid.NewGuid().ToString()[..8]}";
}
