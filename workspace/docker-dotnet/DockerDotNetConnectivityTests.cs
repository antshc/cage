using System.Diagnostics;
using Docker.DotNet;

namespace DockerDotNet.Tests;

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

public class DockerCliConnectivityTests
{
    [Trait("Category", "Integration")]
    [DockerSocketFact]
    public async Task DockerInfo_WhenSocketAvailable_ExitsZeroWithOutput()
    {
        var psi = new ProcessStartInfo("docker", "info --format \"{{.ServerVersion}}\"")
        {
            RedirectStandardOutput = true,
            UseShellExecute = false,
        };

        using var process = Process.Start(psi)!;
        string stdout = await process.StandardOutput.ReadToEndAsync();
        await process.WaitForExitAsync();

        Assert.Equal(0, process.ExitCode);
        Assert.False(string.IsNullOrWhiteSpace(stdout));
    }
}
