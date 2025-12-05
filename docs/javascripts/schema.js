// JSON-LD structured data for SEO
(function() {
  var schema = {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    "name": "FastMCP Runner",
    "description": "A generic OCI-based runner for MCP (Model Context Protocol) servers. Pulls container images from registries and runs them without requiring a Docker daemon.",
    "applicationCategory": "DeveloperApplication",
    "operatingSystem": "Linux",
    "url": "https://fastmcp-runner.readthedocs.io",
    "downloadUrl": "https://github.com/drengskapur/fastmcp-runner",
    "softwareVersion": "0.1.0",
    "author": {
      "@type": "Organization",
      "name": "Drengskapur",
      "url": "https://github.com/drengskapur"
    },
    "license": "https://www.apache.org/licenses/LICENSE-2.0",
    "codeRepository": "https://github.com/drengskapur/fastmcp-runner",
    "programmingLanguage": ["Shell", "Python"],
    "keywords": [
      "MCP",
      "Model Context Protocol",
      "container",
      "OCI",
      "Docker",
      "Hugging Face",
      "serverless",
      "MCP server",
      "container runner"
    ]
  };

  var script = document.createElement('script');
  script.type = 'application/ld+json';
  script.text = JSON.stringify(schema);
  document.head.appendChild(script);
})();
