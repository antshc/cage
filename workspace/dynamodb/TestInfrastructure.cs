namespace DynamoDb.Tests;

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
