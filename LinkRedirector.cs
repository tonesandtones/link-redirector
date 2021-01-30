using System;
using System.IO;
using System.Linq;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Cosmos.Table;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.Extensions.Logging;

namespace LinkRedirector
{
    public static class LinkRedirector
    {
        private static readonly string AuthorisationSecret = Environment.GetEnvironmentVariable("X-Authorization");

        [FunctionName("aka")]
        public static IActionResult Run(
            [HttpTrigger(AuthorizationLevel.Anonymous, "get", "post", "head", "put", Route = "aka/{alias}")] HttpRequest req,
            [Table("Aka", "aka", "{alias}", Connection = "AzureWebJobsStorage", Take = 1)] Aka aka,
            [Table("Aka", Connection = "AzureWebJobsStorage")] out Aka output,
            ILogger log,
            string alias = "400")
        {
            output = default;
            log.LogInformation("alias={alias}, PK={pk}, RK={rk}, Url={url}",
                alias,
                aka?.PartitionKey,
                aka?.RowKey,
                aka?.Url);

            if (alias == "400" || string.IsNullOrEmpty(alias))
            {
                return new BadRequestResult();
            }

            // Create
            if (req.Method == "POST" || req.Method == "PUT")
            {
                if (req.Headers.TryGetValue("X-Authorization", out var values) &&
                    values.FirstOrDefault() == AuthorisationSecret)
                {
                    using var reader = new StreamReader(req.Body);
                    var url = reader.ReadToEnd();
                    if (aka != null)
                        aka.Url = url;
                    else
                        aka = new Aka {RowKey = alias, Url = url};

                    output = aka;
                    return new RedirectResult(url);
                }
                else
                {
                    return new UnauthorizedResult();
                }
            }

            if (aka == null)
                return new NotFoundResult();

            return new RedirectResult(aka.Url);
        }
    }

    public class Aka
    {
        string rowKey = "400";

        public string PartitionKey { get; set; } = "aka";

        public string RowKey
        {
            get => rowKey;
            set
            {
                if (!string.IsNullOrEmpty(value))
                    rowKey = value;
            }
        }

        public string Url { get; set; }
        public string ETag { get; } = "*";
    }
}