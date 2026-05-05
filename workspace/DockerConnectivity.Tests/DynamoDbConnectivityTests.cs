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

    private DockerClient _docker = null!;
    private string _containerName = null!;
    private string _containerHost = "127.0.0.1";

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

    private async Task<string> CreateAndStartContainerAsync()
    {
        await CreateContainerAsync();
        await StartContainerAsync();
        return "127.0.0.1";
    }

    private async Task CreateContainerAsync()
    {
        string containerTcpPort = $"{DefaultDynamoDbPort}/tcp";
        var hostConfig = new HostConfig
        {
            PortBindings = new Dictionary<string, IList<PortBinding>>
            {
                { containerTcpPort, [new PortBinding { HostPort = DefaultDynamoDbPort.ToString() }] }
            }
        };

        await _docker.Containers.CreateContainerAsync(new CreateContainerParameters
        {
            Image = $"{ImageName}:{ImageTag}",
            Name = _containerName,
            Cmd = ["-jar", "DynamoDBLocal.jar", "-inMemory"],
            ExposedPorts = new Dictionary<string, EmptyStruct> { [containerTcpPort] = new EmptyStruct() },
            HostConfig = hostConfig,
        });
    }

    private async Task StartContainerAsync()
    {
        var containers = await _docker.Containers.ListContainersAsync(
            new ContainersListParameters { All = true });

        var container = containers.FirstOrDefault(c => c.Names.Contains($"/{_containerName}"))
            ?? throw new InvalidOperationException($"Container '{_containerName}' not found.");

        if (container.State == "running")
            return;

        bool started = await _docker.Containers.StartContainerAsync(
            container.ID, new ContainerStartParameters());

        if (!started)
            throw new InvalidOperationException($"Failed to start DynamoDB container '{_containerName}'.");
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
