# pull_top100_dreamstate.ps1
#
# Top 100 benchmark pull for Druid-Dreamstate (WCL classID 2 / specID 6) - a
# distinct real spec from the already-tracked Druid-Restoration (specID 4), NOT
# a real retail/Classic Blizzard talent tree - confirmed against
# data\Classes\classes.json, which lists other invented hybrid specs per class
# on this custom "Fresh" realm too (e.g. Paladin "Justicar"). Built as a new,
# fully parallel class-track (own data\Classes\Dreamstate\ folder/manifest/
# cooldown table), same "add a new class" playbook already used for Shaman/
# Priest/Paladin - see WORKFLOW.md's "v2 GraphQL API" section and CLAUDE.md's
# "if a fifth class is ever added" checklist.
#
# REAL vs. PIPELINE class identity (the one genuinely new wrinkle vs. every
# prior port - every earlier class's own $className doubled as both its real
# WCL className AND its data\Classes\ folder key, since spec was always
# implicit/1:1 with class for Druid/Shaman/Priest/Paladin's tracked builds.
# Dreamstate breaks that: it's a SPEC of the real WCL class "Druid", not a
# class of its own):
#   $className    = "Dreamstate"  <- pipeline key: data\Classes\Dreamstate\,
#                                     manifest.className, cooldown-guid-table
#                                     key in build_boss_report_data.ps1 /
#                                     summarize_class_benchmarks.ps1
#   $wclClassName = "Druid"       <- the REAL WCL characterRankings(className:)
#                                     value and table(sourceClass:) value
#   $wclSpecName  = "Dreamstate"  <- the REAL WCL characterRankings(specName:)
#                                     value
# Using "Dreamstate" as the WCL className would be wrong - WCL has no class by
# that name, it only knows Druid/specName=Dreamstate. Keeping the pipeline key
# distinct from "Druid" keeps this entirely separate from the existing
# data\Classes\Druid\ (Restoration) tree - no shared folder, no shared manifest,
# no risk of one class's data corrupting the other's.
#
# REAL DISCOVERY PASS (2026-07-16, against Turkeykin's real report
# XJp8vAxzM4KtHYyb, the same report already pulled for Crowns/Lippies) - never
# guess at guids, confirmed live before writing the cooldown table:
#   - Turkeykin plays TWO real specs in this one report: Balance (DPS role) on
#     all 6 SSC bosses, Dreamstate (healer role) on all 4 TK bosses (Al'ar,
#     Void Reaver, Solarian, Kael'thas) - the real case that drove
#     pull_character_TEMPLATE.ps1's new per-fight spec resolution (see that
#     script's own header).
#   - Real confirmed kit across the 4 real Dreamstate fights: Innervate (29166,
#     3 real casts), Lifebloom (33763, the dominant heal, 407 real casts
#     across the 4 fights), Rejuvenation (26981), two real Regrowth ranks
#     (26980, 9858), Faerie Fire (26993, cast for its uptime debuff - see
#     below), Barkskin, Mark of the Wild, real Mana Potion casts (guids
#     28499/41618, "Restore Mana" display name - same manaPotionNameByClass
#     convention as every other class).
#   - CONFIRMED ABSENT from all 4 real fights: Nature's Swiftness (17116),
#     Swiftmend (18562), Tranquility - zero real casts. Not guessed, not
#     assumed from Druid-Restoration's kit just because it's the same base
#     class - checked and genuinely absent.
#   - Rebirth (26994) and Dark Rune (27869) are kept in the table anyway (per
#     explicit instruction, matching Druid-Restoration's own precedent) even
#     though neither had a real cast in these 4 specific fights - both are
#     conditionally-relevant rows already (Rebirth only shows when relevant to
#     a real death; Dark Rune is a class-agnostic consumable choice), so a
#     real 0% this report isn't a sign either belongs to a different class.
#   - Real, surprising finding worth flagging rather than silently normalizing:
#     Turkeykin's own real cast list also includes abilities named "Power of
#     Prayer" (32367), "Blessing of Life" (38332 - the SAME guid already in
#     Priest's own cooldown table), and "Mental Protection Field" (36480) -
#     genuine evidence this custom realm's Dreamstate kit borrows/renames
#     spell effects across class boundaries as part of its own homebrew
#     design, not a data error. None of these three are added to the
#     cooldown table below (none showed a real, repeatable per-fight pattern
#     worth a standing tracked row - single incidental casts), but worth
#     remembering if a future Dreamstate discovery pass sees them again.
#
# IMPROVED FAERIE FIRE UPTIME - the real mechanism, found live (NOT what was
# originally assumed): base Faerie Fire's debuff effect does NOT appear as a
# discrete applydebuff/removedebuff event anywhere in real data - checked via
# events(dataType: Debuffs) both scoped to Turkeykin's own casts AND completely
# unscoped (every real debuff from every real raid member) across all 4 real
# fights, zero matches for guid 26993 in any of them. Also cross-checked
# against table(dataType: Debuffs) - the SAME raid-wide aggregation the WCL
# website itself renders - for all 4 fights: 7-23 real debuffs each, none
# Faerie-Fire-related. A second real Druid in the same raid (Livtyler) also
# casts Faerie Fire and shows the same absence - not a "someone else covers it"
# case, the debuff-event stream genuinely doesn't carry this effect on this
# server. BUT: table(dataType: Casts, sourceID:) DOES carry a real "uptime"
# (ms) field per ability entry for duration-based effects (Faerie Fire gets
# the same "type": 8 classification as Lifebloom/Rejuvenation/Regrowth in the
# real response) - confirmed real, plausible, consistent values across all 4
# fights (63.9%, 75%, 60.7%, 47%) even though no discrete debuff timeline
# exists for it. Get-ImprovedFaerieFireUptimeLocal below reads this field
# directly - there is nothing to interval-reconstruct, WCL already computes
# it, so this is NOT built as an event-based function parallel to
# Get-TreeOfLifeUptimeLocal the way originally planned. Source-scoped to the
# analyzed character (via the sourceID: filter), same scoping model as Tree of
# Life - not a raid-wide/other-caster-inclusive metric.
#
# Everything else (manifest load/save, the active/archived diff/re-entry
# algorithm, the runspace-pool worker pattern, the shared $fightsCache/
# $actorNamesCache/$deathsClaimed/$abilityCache ConcurrentDictionaries) is
# copied verbatim from pull_top100_druid.ps1, same as every prior class port -
# all of it is genuinely class-agnostic.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File pull_top100_dreamstate.ps1
#   powershell -ExecutionPolicy Bypass -File pull_top100_dreamstate.ps1 -MaxThreads 5

param(
    [int]$MaxThreads = 10,
    [string]$ClassesRoot = "data\Classes"  # override for equivalence-testing into a scratch folder
)

Import-Module (Join-Path $PSScriptRoot "lib\WclV2Api.psm1") -Force

$classesRoot = $ClassesRoot
$className = "Dreamstate"   # pipeline key - see header comment above
$wclClassName = "Druid"     # real WCL className
$wclSpecName = "Dreamstate" # real WCL specName
$classID = 2                # Druid's real WCL classID
$specID = 6                 # Dreamstate's real WCL specID (data\Classes\classes.json)
$classDir = Join-Path $classesRoot $className
$activeDir = Join-Path $classDir "active"
$archivedDir = Join-Path $classDir "archived"
$manifestPath = Join-Path $classDir "manifest.json"
$today = Get-Date -Format "yyyy-MM-dd"
$nowIso = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$token = Get-WclAccessToken
Write-Host "Running with -MaxThreads $MaxThreads (default 10 - lower this if you see rate-limit failures)"
Write-Host "Today: $today"
Write-Host ""

# boss name -> (rankings filename, encounter ID). Same shared, class-independent
# boss table every other pull_top100_*.ps1 script uses.
$bosses = [ordered]@{
    "Maulgar"     = @{ file = "rankings_maulgar.json";     encounterID = 50649 }
    "Gruul"       = @{ file = "rankings_gruul.json";       encounterID = 50650 }
    "Magtheridon" = @{ file = "rankings_magtheridon.json"; encounterID = 50651 }
    "Hydross"    = @{ file = "rankings_hydross.json";    encounterID = 100623 }
    "Lurker"     = @{ file = "rankings_lurker.json";     encounterID = 100624 }
    "Leotheras"  = @{ file = "rankings_leotheras.json";  encounterID = 100625 }
    "Karathress" = @{ file = "rankings_karathress.json"; encounterID = 100626 }
    "Morogrim"   = @{ file = "rankings_morogrim.json";   encounterID = 100627 }
    "Vashj"      = @{ file = "rankings_vashj.json";      encounterID = 100628 }
    "Alar"       = @{ file = "rankings_alar.json";       encounterID = 100730 }
    "VoidReaver" = @{ file = "rankings_voidreaver.json"; encounterID = 100731 }
    "Solarian"   = @{ file = "rankings_solarian.json";   encounterID = 100732 }
    "Kaelthas"   = @{ file = "rankings_kaelthas.json";   encounterID = 100733 }
}

New-Item -ItemType Directory -Force -Path $activeDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $archivedDir "rankings_history") | Out-Null

# ===== Manifest load/save - unchanged, class-agnostic ===== =====
function ConvertTo-OrderedHashtableLocal {
    param($InputObject)
    if ($InputObject -is [System.Array]) {
        return @($InputObject | ForEach-Object { ConvertTo-OrderedHashtableLocal $_ })
    } elseif ($InputObject -is [PSCustomObject]) {
        $hash = [ordered]@{}
        foreach ($prop in $InputObject.PSObject.Properties) {
            $hash[$prop.Name] = ConvertTo-OrderedHashtableLocal $prop.Value
        }
        return $hash
    } else {
        return $InputObject
    }
}

if (Test-Path $manifestPath) {
    $manifest = ConvertTo-OrderedHashtableLocal (Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json)
} else {
    Write-Host "No manifest.json found - creating a fresh one for $className."
    $manifest = [ordered]@{
        schemaVersion = 2
        className = $className
        classID = $classID
        specID = $specID
        benchmarkGeneratedDate = $null
        bosses = [ordered]@{}
    }
}

function Save-ManifestLocal {
    param($Manifest, $Path)
    $jsonText = $Manifest | ConvertTo-Json -Depth 12
    [System.IO.File]::WriteAllText($Path, $jsonText, (New-Object System.Text.UTF8Encoding $false))
}

# ===== Self-contained per-parse worker - same isolated-runspace pattern as
# every other class's Top 100 script. =====
$workerScript = {
    param(
        $reportID, $fightID, $playerName, $i, $wclClassName,
        $outDir, $fightsCache, $actorNamesCache, $deathsClaimed, $abilityCache,
        $accessToken, $moduleAbsolutePath
    )

    Import-Module $moduleAbsolutePath -Force

    $result = [PSCustomObject]@{
        Ok = $true
        Messages = New-Object System.Collections.Generic.List[string]
        ReportID = $reportID
        FightID = $fightID
        PlayerName = $playerName
        SafeName = $null
    }

    function Resolve-AbilityNameLocal($guid) {
        $key = [int]$guid
        $cached = $null
        if ($abilityCache.TryGetValue($key, [ref]$cached)) { return $cached }
        $q = "query { gameData { ability(id: $key) { name icon } } }"
        $r = Invoke-WclGraphQL -Query $q -AccessToken $accessToken
        $entry = [PSCustomObject]@{ Name = $null; Icon = $null }
        if (-not $r.Errors -and $r.Data.gameData.ability) {
            $entry.Name = $r.Data.gameData.ability.name
            $entry.Icon = $r.Data.gameData.ability.icon
        }
        [void]$abilityCache.TryAdd($key, $entry)
        return $entry
    }

    function Get-EventsLocal {
        param($View, $OutFile, $StartTime, $EndTime, $SourceID, $SourceName, $ActorNames)
        if (Test-Path $OutFile) { return $true }

        $dataType = if ($View -eq "healing") { "Healing" } else { "Casts" }
        $queryBuilder = {
            param($pageStartTime)
            "query { reportData { report(code: `"$reportID`") { events(fightIDs: [$fightID], sourceID: $SourceID, dataType: $dataType, includeResources: true, startTime: $pageStartTime, endTime: $EndTime) { data nextPageTimestamp } } } }"
        }.GetNewClosure()
        $extractPage = {
            param($data)
            [PSCustomObject]@{
                Items = @($data.reportData.report.events.data)
                NextPageTimestamp = $data.reportData.report.events.nextPageTimestamp
            }
        }
        $paged = Invoke-WclGraphQLPaged -QueryBuilder $queryBuilder -ExtractPage $extractPage -AccessToken $accessToken -InitialStartTime $StartTime
        if ($paged.Errors) {
            $result.Messages.Add("[$i] FAILED $View events for $reportID/$fightID ($playerName) - $($paged.Errors | ConvertTo-Json -Compress)")
            return $false
        }

        $events = @($paged.Items)
        foreach ($ev in $events) {
            $srcName = if ($ActorNames.ContainsKey([int]$ev.sourceID)) { $ActorNames[[int]$ev.sourceID] } else { "Unknown_$($ev.sourceID)" }
            $tgtName = if ($ev.targetID -ne $null -and $ActorNames.ContainsKey([int]$ev.targetID)) { $ActorNames[[int]$ev.targetID] } else { if ($ev.targetID -ne $null) { "Unknown_$($ev.targetID)" } else { $srcName } }
            $abilityInfo = Resolve-AbilityNameLocal $ev.abilityGameID
            $ev | Add-Member -NotePropertyName "sourceName" -NotePropertyValue $srcName -Force
            $ev | Add-Member -NotePropertyName "targetName" -NotePropertyValue $tgtName -Force
            $ev | Add-Member -NotePropertyName "ability" -NotePropertyValue ([PSCustomObject]@{
                name        = $abilityInfo.Name
                guid        = $ev.abilityGameID
                abilityIcon = $abilityInfo.Icon
            }) -Force
        }
        $totalAmount = ($events | Measure-Object -Property amount -Sum -ErrorAction SilentlyContinue).Sum
        if ($null -eq $totalAmount) { $totalAmount = 0 }
        $totalOverheal = ($events | Measure-Object -Property overheal -Sum -ErrorAction SilentlyContinue).Sum
        if ($null -eq $totalOverheal) { $totalOverheal = 0 }
        $out = [PSCustomObject]@{
            sourceID = $SourceID; sourceName = $SourceName; view = $View
            eventCount = $events.Count; totalAmount = $totalAmount; totalOverheal = $totalOverheal
            events = $events
        }
        $jsonText = $out | ConvertTo-Json -Depth 15
        [System.IO.File]::WriteAllText($OutFile, $jsonText, (New-Object System.Text.UTF8Encoding $false))
        if ($events.Count -ge 2900) {
            $result.Messages.Add("[$i] $reportID/$fightID ($playerName) - $View events: $($events.Count) (HIGH - verify not silently capped)")
        }
        return $true
    }

    # --- fetch (or reuse) this report's fight list + actor-name lookup ---
    if (-not $fightsCache.ContainsKey($reportID)) {
        $reportQuery = "query { reportData { report(code: `"$reportID`") { fights { id startTime endTime } masterData { actors { id name } } } } }"
        $r = Invoke-WclGraphQL -Query $reportQuery -AccessToken $accessToken
        if ($r.Errors -or -not $r.Data.reportData.report) {
            $result.Ok = $false
            $result.Messages.Add("[$i] FAILED fetching report $reportID (fights list) - $($r.Errors | ConvertTo-Json -Compress)")
            return $result
        }
        $report = $r.Data.reportData.report
        $fd = [PSCustomObject]@{
            fights = @($report.fights | ForEach-Object { [PSCustomObject]@{ id = $_.id; start_time = [int64]$_.startTime; end_time = [int64]$_.endTime } })
        }
        [void]$fightsCache.TryAdd($reportID, $fd)

        $names = @{}
        foreach ($actor in $report.masterData.actors) {
            if ($actor.id -ne $null) { $names[[int]$actor.id] = $actor.name }
        }
        [void]$actorNamesCache.TryAdd($reportID, $names)

        $actorLookupByName = @{}
        foreach ($actor in $report.masterData.actors) {
            if ($actor.name) { $actorLookupByName[$actor.name] = $actor.id }
        }
        [void]$fightsCache.TryAdd("$reportID|actorsByName", $actorLookupByName)
    }

    $fightsData = $fightsCache[$reportID]
    $fight = $fightsData.fights | Where-Object { $_.id -eq $fightID }
    if (-not $fight) {
        $result.Ok = $false
        $result.Messages.Add("[$i] SKIP: fight $fightID not found in report $reportID")
        return $result
    }

    $actorLookupByName = $fightsCache["$reportID|actorsByName"]
    if (-not $actorLookupByName.ContainsKey($playerName)) {
        $result.Ok = $false
        $result.Messages.Add("[$i] SKIP: '$playerName' not found in report $reportID actors[] (can't scope sourceID)")
        return $result
    }
    $playerID = $actorLookupByName[$playerName]
    $actorNames = $actorNamesCache[$reportID]
    $start = $fight.start_time
    $end = $fight.end_time
    $safeName = ($playerName -replace '[\\/:*?"<>|]', '_')
    $result.SafeName = $safeName

    $parseOk = $true

    $healingOutFile = Join-Path $outDir "$($reportID)_$($fightID)_$($safeName)_healing_events.json"
    if (-not (Get-EventsLocal -View "healing" -OutFile $healingOutFile -StartTime $start -EndTime $end -SourceID $playerID -SourceName $playerName -ActorNames $actorNames)) {
        $parseOk = $false
    }

    $castsOutFile = Join-Path $outDir "$($reportID)_$($fightID)_$($safeName)_casts_events.json"
    if (-not (Get-EventsLocal -View "casts" -OutFile $castsOutFile -StartTime $start -EndTime $end -SourceID $playerID -SourceName $playerName -ActorNames $actorNames)) {
        $parseOk = $false
    }

    function Get-ConsumablesSnapshotLocal {
        param($StartTime, $EndTime, $SourceID)
        $bufferMs = 120000
        $queryStart = [Math]::Max(0, $StartTime - $bufferMs)
        $q = "query { reportData { report(code: `"$reportID`") { events(dataType: CombatantInfo, startTime: $queryStart, endTime: $EndTime) { data } } } }"
        $r = Invoke-WclGraphQL -Query $q -AccessToken $accessToken
        if ($r.Errors) {
            $result.Messages.Add("[$i] FAILED combatantinfo for $reportID/$fightID ($playerName) - $($r.Errors | ConvertTo-Json -Compress)")
            return $null
        }
        $allEvents = @($r.Data.reportData.report.events.data)
        $candidates = @($allEvents | Where-Object { $_.sourceID -eq $SourceID })
        if ($candidates.Count -eq 0) {
            $result.Messages.Add("[$i] combatantinfo OK but no entry for sourceID=$SourceID even with backward buffer ($reportID/$fightID, $playerName)")
            return $null
        }
        $closest = $candidates | Sort-Object { [Math]::Abs($_.timestamp - $StartTime) } | Select-Object -First 1
        if (-not $closest.auras) { return $null }
        $consumableClass = Get-ConsumableClassification -Auras $closest.auras
        $flask = $consumableClass.Flask
        $battleElixir = $consumableClass.BattleElixir
        $guardianElixir = $consumableClass.GuardianElixir
        $food = $closest.auras | Where-Object { $_.name -eq 'Well Fed' } | Select-Object -First 1
        return [PSCustomObject]@{
            flaskActive          = [bool]$flask
            flaskName            = if ($flask) { $flask.name } else { $null }
            battleElixirActive   = [bool]$battleElixir
            battleElixirName     = if ($battleElixir) { $battleElixir.name } else { $null }
            guardianElixirActive = [bool]$guardianElixir
            guardianElixirName   = if ($guardianElixir) { $guardianElixir.name } else { $null }
            foodActive           = [bool]$food
            foodName             = if ($food) { $food.name } else { $null }
        }
    }

    # Improved Faerie Fire uptime - NOT an event-interval-reconstruction function
    # like Tree of Life's. Real discovery (see this file's own header) found the
    # debuff never appears via events(dataType: Debuffs), scoped or unscoped,
    # across every real Dreamstate fight checked - but table(dataType: Casts,
    # sourceID:) carries a real "uptime" (ms) field per ability entry that DOES
    # capture it correctly (confirmed real, consistent 47-75% values). Read that
    # field directly instead of reconstructing anything.
    function Get-ImprovedFaerieFireUptimeLocal {
        param($StartTime, $EndTime, $SourceID)
        $faerieFireGuid = 26993
        $q = "query { reportData { report(code: `"$reportID`") { table(fightIDs: [$fightID], dataType: Casts, sourceID: $SourceID, startTime: $StartTime, endTime: $EndTime) } } }"
        $r = Invoke-WclGraphQL -Query $q -AccessToken $accessToken
        if ($r.Errors) {
            $result.Messages.Add("[$i] FAILED improved-faerie-fire casts-table for $reportID/$fightID ($playerName) - $($r.Errors | ConvertTo-Json -Compress)")
            return $null
        }
        $entries = @($r.Data.reportData.report.table.data.entries)
        $ffEntry = $entries | Where-Object { $_.guid -eq $faerieFireGuid } | Select-Object -First 1
        if (-not $ffEntry -or -not $ffEntry.uptime) {
            return 0
        }
        $duration = $EndTime - $StartTime
        if ($duration -le 0) { return 0 }
        return [math]::Round(($ffEntry.uptime / $duration) * 100, 1)
    }

    $consumablesOutFile = Join-Path $outDir "$($reportID)_$($fightID)_$($safeName)_consumables.json"
    if (-not (Test-Path $consumablesOutFile)) {
        $snapshot = Get-ConsumablesSnapshotLocal -StartTime $start -EndTime $end -SourceID $playerID
        if ($null -eq $snapshot) {
            $parseOk = $false
        } else {
            $improvedFaerieFirePct = Get-ImprovedFaerieFireUptimeLocal -StartTime $start -EndTime $end -SourceID $playerID
            if ($null -eq $improvedFaerieFirePct) {
                $improvedFaerieFirePct = 0
                $parseOk = $false
            }
            $out = [PSCustomObject]@{
                flaskActive          = $snapshot.flaskActive
                flaskName            = $snapshot.flaskName
                battleElixirActive   = $snapshot.battleElixirActive
                battleElixirName     = $snapshot.battleElixirName
                guardianElixirActive = $snapshot.guardianElixirActive
                guardianElixirName   = $snapshot.guardianElixirName
                foodActive           = $snapshot.foodActive
                foodName             = $snapshot.foodName
                improvedFaerieFireUptimePct = $improvedFaerieFirePct
            }
            $jsonText = $out | ConvertTo-Json -Depth 5
            [System.IO.File]::WriteAllText($consumablesOutFile, $jsonText, (New-Object System.Text.UTF8Encoding $false))
        }
    }

    # active time - real WCL sourceClass filter uses the REAL className ("Druid"),
    # not the pipeline key ("Dreamstate") - WCL has no class literally named
    # "Dreamstate".
    $activeTimeOutFile = Join-Path $outDir "$($reportID)_$($fightID)_$($safeName)_activetime.json"
    if (-not (Test-Path $activeTimeOutFile)) {
        $atQuery = "query { reportData { report(code: `"$reportID`") { table(fightIDs: [$fightID], dataType: Healing, sourceClass: `"$wclClassName`", startTime: $start, endTime: $end) } } }"
        $atResult = Invoke-WclGraphQL -Query $atQuery -AccessToken $accessToken
        if ($atResult.Errors) {
            $result.Messages.Add("[$i] FAILED activetime healing-table call for $reportID/$fightID ($playerName) - $($atResult.Errors | ConvertTo-Json -Compress)")
            $parseOk = $false
        } else {
            $atEntry = $atResult.Data.reportData.report.table.data.entries | Where-Object { $_.name -eq $playerName } | Select-Object -First 1
            if (-not $atEntry) {
                $result.Messages.Add("[$i] FAILED activetime for $reportID/$fightID ($playerName) - no matching entry in healing table response")
                $parseOk = $false
            } else {
                $duration = $end - $start
                $activeTimePct = if ($duration -gt 0) { [math]::Round(($atEntry.activeTime / $duration) * 100, 1) } else { 0 }
                $activeTimeReducedPct = if ($duration -gt 0) { [math]::Round(($atEntry.activeTimeReduced / $duration) * 100, 1) } else { 0 }
                $atOut = [PSCustomObject]@{
                    activeTime = $atEntry.activeTime
                    activeTimeReduced = $atEntry.activeTimeReduced
                    activeTimePct = $activeTimePct
                    activeTimeReducedPct = $activeTimeReducedPct
                }
                $jsonText = $atOut | ConvertTo-Json -Depth 5
                [System.IO.File]::WriteAllText($activeTimeOutFile, $jsonText, (New-Object System.Text.UTF8Encoding $false))
            }
        }
    }

    # --- deaths (fight-wide, once per report+fight, NEVER archived) ---
    $deathsOutFile = Join-Path $outDir "$($reportID)_$($fightID)_deaths.json"
    if (-not (Test-Path $deathsOutFile)) {
        $deathsKey = "$reportID|$fightID"
        if ($deathsClaimed.TryAdd($deathsKey, $true)) {
            $deathsQuery = "query { reportData { report(code: `"$reportID`") { table(fightIDs: [$fightID], dataType: Deaths, startTime: $start, endTime: $end) } } }"
            $deathsResult = Invoke-WclGraphQL -Query $deathsQuery -AccessToken $accessToken
            if ($deathsResult.Errors) {
                $result.Messages.Add("[$i] FAILED deaths table for $reportID/$fightID - $($deathsResult.Errors | ConvertTo-Json -Compress)")
            } else {
                $jsonText = $deathsResult.Data.reportData.report.table.data | ConvertTo-Json -Depth 12
                [System.IO.File]::WriteAllText($deathsOutFile, $jsonText, (New-Object System.Text.UTF8Encoding $false))
            }
        }
        if (-not (Test-Path $deathsOutFile)) {
            $parseOk = $false
        }
    }

    $result.Ok = $parseOk
    return $result
}

$fightsCache = [System.Collections.Concurrent.ConcurrentDictionary[string,object]]::new()
$actorNamesCache = [System.Collections.Concurrent.ConcurrentDictionary[string,object]]::new()
$deathsClaimed = [System.Collections.Concurrent.ConcurrentDictionary[string,bool]]::new()
$abilityCache = [System.Collections.Concurrent.ConcurrentDictionary[int,object]]::new()

$totalNew = 0
$totalConfirmed = 0
$totalArchived = 0
$totalReentered = 0
$totalFailed = 0

foreach ($bossName in $bosses.Keys) {
    $encounterID = $bosses[$bossName].encounterID
    $rankingsFileName = $bosses[$bossName].file
    $activeRankingsPath = Join-Path $activeDir $rankingsFileName
    $bossActiveDir = Join-Path $activeDir $bossName
    $bossArchivedDir = Join-Path $archivedDir $bossName
    New-Item -ItemType Directory -Force -Path $bossActiveDir | Out-Null

    Write-Host "=== $bossName ==="

    # Real WCL className/specName - "Druid"/"Dreamstate", not the pipeline key.
    $rankingsQuery = "query { worldData { encounter(id: $encounterID) { characterRankings(className: `"$wclClassName`", specName: `"$wclSpecName`", metric: hps, page: 1) } } }"
    $rankingsResult = Invoke-WclGraphQL -Query $rankingsQuery -AccessToken $token
    if ($rankingsResult.Errors -or -not $rankingsResult.Data.worldData.encounter.characterRankings) {
        Write-Host "  FAILED fetching rankings - $($rankingsResult.Errors | ConvertTo-Json -Compress) - skipping this boss entirely this run."
        Write-Host ""
        continue
    }
    $freshRankingsData = $rankingsResult.Data.worldData.encounter.characterRankings
    $freshRankings = @($freshRankingsData.rankings)

    $reshapedForDisk = @($freshRankings | ForEach-Object {
        [PSCustomObject]@{
            name     = $_.name
            reportID = $_.report.code
            fightID  = $_.report.fightID
            duration = $_.duration
            total    = $_.amount
        }
    })
    Write-Host "  got $($freshRankings.Count) fresh rankings"

    if (-not $manifest.bosses.Contains($bossName)) {
        $manifest.bosses[$bossName] = [ordered]@{
            encounterID = $encounterID
            lastPulledDate = $null
            rankingsSnapshotDate = $null
            parses = [ordered]@{}
        }
    }
    $bossEntry = $manifest.bosses[$bossName]

    $freshByKey = [ordered]@{}
    for ($k = 0; $k -lt $freshRankings.Count; $k++) {
        $r = $freshRankings[$k]
        $key = "$($r.report.code)_$($r.report.fightID)_$($r.name)"
        $freshByKey[$key] = [ordered]@{ rank = $k + 1; hps = $r.amount; reportID = $r.report.code; fightID = $r.report.fightID; name = $r.name }
    }

    $activeManifestKeys = @($bossEntry.parses.Keys | Where-Object { $bossEntry.parses[$_].status -eq "active" })
    $archivedManifestKeys = @($bossEntry.parses.Keys | Where-Object { $bossEntry.parses[$_].status -eq "archived" })
    $newKeys = @($freshByKey.Keys | Where-Object { -not $bossEntry.parses.Contains($_) })
    $reenteredKeys = @($freshByKey.Keys | Where-Object { $archivedManifestKeys -contains $_ })
    $droppedKeys = @($activeManifestKeys | Where-Object { -not $freshByKey.Contains($_) })
    $stillActiveKeys = @($activeManifestKeys | Where-Object { $freshByKey.Contains($_) })

    foreach ($key in $stillActiveKeys) {
        $bossEntry.parses[$key].rank = $freshByKey[$key].rank
        $bossEntry.parses[$key].hps = [math]::Round($freshByKey[$key].hps, 1)
        $bossEntry.parses[$key].lastConfirmedInTop100At = $nowIso
    }
    $totalConfirmed += $stillActiveKeys.Count

    if ($droppedKeys.Count -gt 0) {
        New-Item -ItemType Directory -Force -Path $bossArchivedDir | Out-Null
    }
    foreach ($key in $droppedKeys) {
        $p = $bossEntry.parses[$key]
        $stem = "$($p.reportID)_$($p.fightID)_$($p.safeName)"
        foreach ($suffix in @("healing_events", "casts_events", "consumables", "activetime")) {
            $srcPath = Join-Path $bossActiveDir "$($stem)_$($suffix).json"
            if (Test-Path $srcPath) {
                Move-Item -Path $srcPath -Destination $bossArchivedDir -Force
            } elseif ($suffix -ne "activetime") {
                Write-Host "  WARNING: expected $srcPath to archive for dropped parse $key, not found."
            }
        }
        $p.status = "archived"
        $p.archivedAt = $nowIso
    }
    $totalArchived += $droppedKeys.Count

    foreach ($key in $reenteredKeys) {
        $p = $bossEntry.parses[$key]
        $stem = "$($p.reportID)_$($p.fightID)_$($p.safeName)"
        foreach ($suffix in @("healing_events", "casts_events", "consumables", "activetime")) {
            $srcPath = Join-Path $bossArchivedDir "$($stem)_$($suffix).json"
            if (Test-Path $srcPath) {
                Move-Item -Path $srcPath -Destination $bossActiveDir -Force
            } elseif ($suffix -ne "activetime") {
                Write-Host "  WARNING: expected $srcPath to restore for re-entered parse $key, not found in archived\$bossName."
            }
        }
        $p.status = "active"
        $p.archivedAt = $null
        $p.rank = $freshByKey[$key].rank
        $p.hps = [math]::Round($freshByKey[$key].hps, 1)
        $p.lastConfirmedInTop100At = $nowIso
    }
    if ($reenteredKeys.Count -gt 0) {
        $totalReentered += $reenteredKeys.Count
        Write-Host "  $($reenteredKeys.Count) parse(s) RE-ENTERED the Top 100 (restored from archived\, zero API calls): $($reenteredKeys -join ', ')"
    }

    $changed = ($newKeys.Count -gt 0) -or ($droppedKeys.Count -gt 0) -or ($reenteredKeys.Count -gt 0)
    if ($changed) {
        if (Test-Path $activeRankingsPath) {
            $oldSnapshotDate = $bossEntry.rankingsSnapshotDate
            if (-not $oldSnapshotDate) { $oldSnapshotDate = "unknown-date" }
            $rankingsHistoryDir = Join-Path (Join-Path $archivedDir "rankings_history") $bossName
            New-Item -ItemType Directory -Force -Path $rankingsHistoryDir | Out-Null
            $archivedRankingsPath = Join-Path $rankingsHistoryDir "$oldSnapshotDate.json"
            Move-Item -Path $activeRankingsPath -Destination $archivedRankingsPath -Force
        }
        $rankingsOut = [PSCustomObject]@{ rankings = $reshapedForDisk }
        $rankingsJsonText = $rankingsOut | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($activeRankingsPath, $rankingsJsonText, (New-Object System.Text.UTF8Encoding $false))
        $bossEntry.rankingsSnapshotDate = $today
        Write-Host "  rankings CHANGED ($($newKeys.Count) new, $($droppedKeys.Count) dropped, $($reenteredKeys.Count) re-entered) - snapshot updated"
    } else {
        Write-Host "  rankings unchanged since $($bossEntry.rankingsSnapshotDate) - not rewriting active\$rankingsFileName"
    }
    $bossEntry.lastPulledDate = $today

    if ($newKeys.Count -eq 0) {
        Write-Host "  no new parses to fetch"
        Save-ManifestLocal -Manifest $manifest -Path $manifestPath
        Write-Host ""
        continue
    }

    Write-Host "  fetching $($newKeys.Count) new parses ($MaxThreads threads)..."
    $moduleAbsolutePath = Join-Path $PSScriptRoot "lib\WclV2Api.psm1"
    $pool = [runspacefactory]::CreateRunspacePool(1, $MaxThreads)
    $pool.Open()

    $jobs = New-Object System.Collections.Generic.List[object]
    $i = 0
    foreach ($key in $newKeys) {
        $i++
        $entry = $freshByKey[$key]
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool
        [void]$ps.AddScript($workerScript.ToString()).
            AddArgument($entry.reportID).
            AddArgument($entry.fightID).
            AddArgument($entry.name).
            AddArgument($i).
            AddArgument($wclClassName).
            AddArgument($bossActiveDir).
            AddArgument($fightsCache).
            AddArgument($actorNamesCache).
            AddArgument($deathsClaimed).
            AddArgument($abilityCache).
            AddArgument($token).
            AddArgument($moduleAbsolutePath)
        $handle = $ps.BeginInvoke()
        $jobs.Add([PSCustomObject]@{ Pipe = $ps; Handle = $handle; Key = $key })
    }

    $bossNewOk = 0
    $bossNewFailed = 0
    foreach ($job in $jobs) {
        try {
            $result = $job.Pipe.EndInvoke($job.Handle)
            foreach ($msg in $result.Messages) { Write-Host "  $msg" }
            if ($result.Ok) {
                $entry = $freshByKey[$job.Key]
                $bossEntry.parses[$job.Key] = [ordered]@{
                    reportID = $result.ReportID
                    fightID = $result.FightID
                    playerName = $result.PlayerName
                    safeName = $result.SafeName
                    status = "active"
                    rank = $entry.rank
                    hps = [math]::Round($entry.hps, 1)
                    firstSeenAt = $nowIso
                    lastConfirmedInTop100At = $nowIso
                    archivedAt = $null
                }
                $bossNewOk++
            } else {
                $bossNewFailed++
            }
        } catch {
            Write-Host "  Worker threw unexpectedly for $($job.Key): $_"
            $bossNewFailed++
        } finally {
            $job.Pipe.Dispose()
        }
    }

    $pool.Close()
    $pool.Dispose()

    Write-Host "  $bossName new parses done: $bossNewOk ok, $bossNewFailed failed"
    $totalNew += $bossNewOk
    $totalFailed += $bossNewFailed

    Save-ManifestLocal -Manifest $manifest -Path $manifestPath
    Write-Host ""
}

Write-Host "=================================="
Write-Host "Done."
Write-Host "  New parses fetched (ok):        $totalNew"
Write-Host "  New parses failed:              $totalFailed"
Write-Host "  Still-active (no refetch):      $totalConfirmed"
Write-Host "  Archived (dropped from Top 100): $totalArchived"
Write-Host "  Re-entered (restored, no refetch): $totalReentered"
Write-Host "  Unique reports fetched:         $($fightsCache.Count)"
Write-Host "  manifest.json:                  $manifestPath"
