using System.Diagnostics;
using Docker.DotNet;

namespace DockerDotNet.Tests;

public class DockerDotNetConnectivityTests
{
    [Fact]
    public async Task PingAsync_WhenSocketAvailable_Succeeds()
    {
        using DockerClient client = new DockerClientConfiguration().CreateClient();

        // PingAsync returns void; if it throws, the test fails
        await client.System.PingAsync();
    }
}

public class DockerCliConnectivityTests
{
    [Fact]
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
