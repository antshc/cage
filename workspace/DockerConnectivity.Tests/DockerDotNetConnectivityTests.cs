using Docker.DotNet;

namespace DockerConnectivity.Tests;

/// <summary>Skips the test when the Docker socket is not available on the host.</summary>
public sealed class DockerSocketFactAttribute : FactAttribute
{
    private const string DockerSocketPath = "/var/run/docker.sock";

    public DockerSocketFactAttribute()
    {
        if (!File.Exists(DockerSocketPath))
            Skip = "Docker socket not available";
    }
}

public class DockerDotNetConnectivityTests
{
    [Trait("Category", "Integration")]
    [DockerSocketFact]
    public async Task PingAsync_WhenSocketAvailable_Succeeds()
    {
        using DockerClient client = new DockerClientConfiguration().CreateClient();

        // PingAsync returns void; if it throws, the test fails
        await client.System.PingAsync();
    }
}
