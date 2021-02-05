using System;
using System.Linq;
using LinkRedirector.Model;
using Microsoft.Azure.WebJobs;
using Microsoft.Extensions.Logging;
using Microsoft.Azure.Cosmos.Table;

namespace LinkRedirector
{
    public class StatsCollector
    {
        private const string timerSchedule = "0 */5 * * * *";
        
        [FunctionName("StatsCollector")]
        public void Run(
            [TimerTrigger(timerSchedule)] TimerInfo timerInfo,
            [Table("stats", Connection = "AzureWebJobsStorage")] CloudTable statsTable,
            [Table("aka", Connection = "AzureWebJobsStorage")] CloudTable akaTable,
            [Table("stats", Connection = "AzureWebJobsStorage")] IAsyncCollector<Stats> statsOutput,
            ILogger logger
        )
        {
            logger.LogInformation("hurro");
            
            var akaQuery = new TableQuery<Aka>().Where(
                TableQuery.GenerateFilterCondition("PartitionKey", QueryComparisons.Equal, Aka.DefaultPartitionKey));
            var akas = akaTable.ExecuteQuery(akaQuery);
            
            //these are the list of all the aliases we need to generates stats for
            var akaAliases = akas.Select(x => x.RowKey).ToHashSet();
            
            var statsQuery = new TableQuery<Stats>().Where(
                TableQuery.GenerateFilterCondition("PartitionKey", QueryComparisons.Equal, Stats.DefaultPartitionKey));
            var statss = statsTable.ExecuteQuery(statsQuery).ToList();
            var statssAlises = statss.Select(x => x.RowKey).ToHashSet();
            
            //any statss that aren't in akaAliases, drop them from statss
            //any akaAliases that aren't in statss, create a new empty Stats with the right rowkey
            
            var statssToUpdate = statss.Where(x => akaAliases.Contains(x.RowKey));
            var aliasesToAdd = akaAliases.Where(x => !statssAlises.Contains(x));
            statssToUpdate = statssToUpdate.Concat(aliasesToAdd.Select(x => new Stats(x))).ToList();
            
        }

        public class Stats : TableEntity
        {
            public const string DefaultPartitionKey = "stats";

            public Stats()
            {
            }

            public Stats(string rowKey) : base(DefaultPartitionKey, rowKey)
            {
            }

            public int Count { get; set; } = 0;

            /// <summary>
            /// The end time of the last time we queried for this alias
            /// </summary>
            public DateTime LastUpdateEndTime { get; set; } = DateTime.MinValue;

            /// <summary>
            /// The timestamp of the most recent result for the alias
            /// </summary>
            public DateTime LastResultCaptured { get; set; } = DateTime.MinValue;
        }
    }
}