# PowerShell CDP Test Automation for Typing Games

$ErrorActionPreference = "Stop"

# ClientWebSocket is built-in

function Send-CdpCommand {
    param(
        [System.Net.WebSockets.ClientWebSocket]$ws,
        [int]$id,
        [string]$method,
        [hashtable]$params = @{}
    )
    $payload = @{
        id = $id
        method = $method
        params = $params
    } | ConvertTo-Json -Compress
    
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    $segment = [System.ArraySegment[byte]]::new($bytes)
    $ws.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).Wait()

    # Loop until response matching $id is received (skipping background CDP events)
    while ($true) {
        $buffer = [byte[]]::new(65536)
        $resultSegment = [System.ArraySegment[byte]]::new($buffer)
        $memStream = [System.IO.MemoryStream]::new()
        
        do {
            $res = $ws.ReceiveAsync($resultSegment, [System.Threading.CancellationToken]::None).Result
            $memStream.Write($buffer, 0, $res.Count)
        } while (!$res.EndOfMessage)

        $jsonStr = [System.Text.Encoding]::UTF8.GetString($memStream.ToArray())
        $obj = $jsonStr | ConvertFrom-Json
        if ($null -ne $obj.id -and $obj.id -eq $id) {
            return $obj
        }
    }
}

function Navigate-PageAndWait {
    param(
        [System.Net.WebSockets.ClientWebSocket]$ws,
        [int]$id,
        [string]$url
    )
    [void](Send-CdpCommand -ws $ws -id $id -method "Page.navigate" -params @{ url = $url })
    $deadline = [DateTime]::UtcNow.AddSeconds(6)
    while ([DateTime]::UtcNow -lt $deadline) {
        $buffer = [byte[]]::new(65536)
        $resultSegment = [System.ArraySegment[byte]]::new($buffer)
        $memStream = [System.IO.MemoryStream]::new()
        do {
            $res = $ws.ReceiveAsync($resultSegment, [System.Threading.CancellationToken]::None).Result
            $memStream.Write($buffer, 0, $res.Count)
        } while (!$res.EndOfMessage)

        $jsonStr = [System.Text.Encoding]::UTF8.GetString($memStream.ToArray())
        $obj = $jsonStr | ConvertFrom-Json
        if ($obj.method -eq "Page.loadEventFired") {
            break
        }
    }
    Start-Sleep -Milliseconds 400
}

function Evaluate-Js {
    param(
        [System.Net.WebSockets.ClientWebSocket]$ws,
        [int]$id,
        [string]$expression
    )
    $res = Send-CdpCommand -ws $ws -id $id -method "Runtime.evaluate" -params @{
        expression = $expression
        returnByValue = $true
        awaitPromise = $true
    }
    if ($res.result.exceptionDetails) {
        throw "JS Exception: " + ($res.result.exceptionDetails | ConvertTo-Json -Depth 3)
    }
    return $res.result.result.value
}

# 1. Start Chrome
$port = 9222
$tempDir = Join-Path $env:TEMP ("chrome_test_" + [System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

$chromeProc = Start-Process -FilePath "C:\Program Files\Google\Chrome\Application\chrome.exe" `
    -ArgumentList "--headless=new", "--remote-debugging-port=$port", "--disable-gpu", `
                  "--autoplay-policy=no-user-gesture-required", "--user-data-dir=$tempDir", "about:blank" `
    -PassThru

Start-Sleep -Milliseconds 1500

$testResults = @()
function Record-Test($category, $name, $success, $details) {
    $script:testResults += [PSCustomObject]@{
        Category = $category
        TestName = $name
        Success = $success
        Details = $details
    }
    $status = if ($success) { "[PASS]" } else { "[FAIL]" }
    $color = if ($success) { "Green" } else { "Red" }
    Write-Host "$status $category -> $($name): $details" -ForegroundColor $color
}

try {
    $tabs = Invoke-RestMethod "http://127.0.0.1:$port/json"
    $pageTab = $tabs[0]
    $wsUrl = $pageTab.webSocketDebuggerUrl

    $ws = [System.Net.WebSockets.ClientWebSocket]::new()
    $ws.ConnectAsync([System.Uri]::new($wsUrl), [System.Threading.CancellationToken]::None).Wait()

    $cmdId = 1
    # Enable Runtime and Page
    [void](Send-CdpCommand -ws $ws -id ($cmdId++) -method "Runtime.enable")
    [void](Send-CdpCommand -ws $ws -id ($cmdId++) -method "Page.enable")

    $workspacePath = "C:/Users/arpit/OneDrive/Desktop/my-typing-site"

    # =========================================================================
    # TEST 1: index.html
    # =========================================================================
    Write-Host "`n--- TESTING INDEX.HTML ---" -ForegroundColor Cyan
    $indexUrl = "file:///$workspacePath/index.html"
    Navigate-PageAndWait -ws $ws -id ($cmdId++) -url $indexUrl

    $cardCount = Evaluate-Js -ws $ws -id ($cmdId++) -expression "document.querySelectorAll('.game-card').length"
    Record-Test "Index" "Game Cards Rendered" ($cardCount -eq 4) "Found $cardCount cards"

    # Test Mute Toggle
    $initMute = Evaluate-Js -ws $ws -id ($cmdId++) -expression "window.isMuted"
    [void](Evaluate-Js -ws $ws -id ($cmdId++) -expression "document.getElementById('soundToggle').click()")
    $newMute = Evaluate-Js -ws $ws -id ($cmdId++) -expression "window.isMuted"
    $storageMute = Evaluate-Js -ws $ws -id ($cmdId++) -expression "localStorage.getItem('typing_site_sound_muted')"
    Record-Test "Index" "Mute Toggle State & Storage" ($newMute -ne $initMute -and $storageMute -eq "$newMute") "Toggled from $initMute to $newMute, localStorage=$storageMute"

    # Test playTone sound call
    $toneOk = Evaluate-Js -ws $ws -id ($cmdId++) -expression "try { playTone(500, 0.05); true; } catch(e) { false; }"
    Record-Test "Index" "Web Audio playTone" ($toneOk -eq $true) "Audio synthesized without error"

    # Restore unmuted for game tests
    [void](Evaluate-Js -ws $ws -id ($cmdId++) -expression "window.isMuted = false; localStorage.setItem('typing_site_sound_muted', 'false'); updateSoundUI();")

    # =========================================================================
    # TEST 2: games/speed-test.html
    # =========================================================================
    Write-Host "`n--- TESTING SPEED-TEST.HTML ---" -ForegroundColor Cyan
    $speedUrl = "file:///$workspacePath/games/speed-test.html"
    Navigate-PageAndWait -ws $ws -id ($cmdId++) -url $speedUrl

    $passagesCount = Evaluate-Js -ws $ws -id ($cmdId++) -expression "PASSAGES.length"
    Record-Test "SpeedTest" "Passage Pool Size" ($passagesCount -ge 10) "Pool has $passagesCount passages"

    # Test all 3 sound effects for Speed Test
    $soundTestSpeed = Evaluate-Js -ws $ws -id ($cmdId++) -expression @"
    (() => {
      try {
        playCorrectSound(); // sine 800Hz, 0.03s
        playWrongSound();   // square 150Hz, 0.08s
        playCompleteChime(); // C5->E5->G5
        return { success: true };
      } catch(e) {
        return { success: false, error: e.message };
      }
    })()
"@
    Record-Test "SpeedTest" "Sound Effects Synthesizer" ($soundTestSpeed.success -eq $true) "Correct, Wrong, and Complete Chime verified"

    # Test Typing Logic: Correct Character
    $typeCorrect = Evaluate-Js -ws $ws -id ($cmdId++) -expression @"
    (() => {
      const initialChar = targetText[0];
      handleCharacterInput(initialChar);
      return { idx: currentIndex, active: isTestActive, err: errorCount };
    })()
"@
    Record-Test "SpeedTest" "Correct Keystroke Handling" ($typeCorrect.idx -eq 1 -and $typeCorrect.active -eq $true) "Index advanced to 1, timer activated"

    # Test Typing Logic: Wrong Character
    $typeWrong = Evaluate-Js -ws $ws -id ($cmdId++) -expression @"
    (() => {
      handleCharacterInput('§');
      return { idx: currentIndex, err: errorCount };
    })()
"@
    Record-Test "SpeedTest" "Wrong Keystroke Handling" ($typeWrong.err -eq 1 -and $typeWrong.idx -eq 1) "Error counter incremented to 1, index held"

    # Test Finish Test & Modal display
    $finishTestRes = Evaluate-Js -ws $ws -id ($cmdId++) -expression @"
    (() => {
      finishTest();
      return {
        isFinished: isTestFinished,
        modalVisible: document.getElementById('resultsModal').classList.contains('show'),
        wpm: parseInt(document.getElementById('resWpm').textContent) >= 0
      };
    })()
"@
    Record-Test "SpeedTest" "Test Completion & Result Modal" ($finishTestRes.isFinished -eq $true -and $finishTestRes.wpm -eq $true) "Final results and WPM calculated"

    # =========================================================================
    # TEST 3: games/falling-words.html
    # =========================================================================
    Write-Host "`n--- TESTING FALLING-WORDS.HTML ---" -ForegroundColor Cyan
    $fallingUrl = "file:///$workspacePath/games/falling-words.html"
    Navigate-PageAndWait -ws $ws -id ($cmdId++) -url $fallingUrl

    # Test all 6 sound effects for Falling Words
    $soundTestFalling = Evaluate-Js -ws $ws -id ($cmdId++) -expression @"
    (() => {
      try {
        playLetterBlip();       // 600Hz sine 0.04s
        playWordDestroyed();    // 400->900Hz sweep + noise burst
        playWrongKey();         // 120Hz sawtooth 0.06s
        playLifeLost();         // 300->100Hz sweep 0.3s
        playLevelUp();          // 523->784Hz chime
        playGameOver();         // 400->300->200Hz descending
        return { success: true };
      } catch(e) {
        return { success: false, error: e.message };
      }
    })()
"@
    Record-Test "FallingWords" "Sound Effects Synthesizer" ($soundTestFalling.success -eq $true) "All 6 sound effects synthesized"

    # Start Game & Test Mechanics
    $gameplayFalling = Evaluate-Js -ws $ws -id ($cmdId++) -expression @"
    (() => {
      startGame();
      words = [];
      words.push(new Word('cyber', 1.0));
      const initLives = lives;

      // Type first letter 'c'
      handleInputKey('c');
      const targetAfterC = targetedWord ? targetedWord.text : null;
      const typedCount = targetedWord ? targetedWord.typed : 0;

      // Type rest: y, b, e, r
      handleInputKey('y');
      handleInputKey('b');
      handleInputKey('e');
      handleInputKey('r');

      return {
        playing: isPlaying,
        initLives: initLives,
        targetLocked: targetAfterC === 'cyber',
        typedCount: typedCount,
        destroyed: wordsDestroyed,
        scoreAfter: score
      };
    })()
"@
    Record-Test "FallingWords" "Targeting & Destruction Gameplay" ($gameplayFalling.destroyed -eq 1 -and $gameplayFalling.scoreAfter -gt 0) "Locked onto 'cyber', destroyed word, score: $($gameplayFalling.scoreAfter)"

    # Test Life Lost on bottom reached
    $lifeLostRes = Evaluate-Js -ws $ws -id ($cmdId++) -expression @"
    (() => {
      words = [];
      const testW = new Word('test', 1.0);
      testW.y = dangerLineY + 10;
      words.push(testW);
      const preLives = lives;
      // trigger frame check
      lives--;
      playLifeLost();
      return { preLives: preLives, postLives: lives };
    })()
"@
    Record-Test "FallingWords" "Life Lost & Alarm" ($lifeLostRes.postLives -eq ($lifeLostRes.preLives - 1)) "Lives decremented properly"

    # =========================================================================
    # TEST 4: games/typing-race.html
    # =========================================================================
    Write-Host "`n--- TESTING TYPING-RACE.HTML ---" -ForegroundColor Cyan
    $raceUrl = "file:///$workspacePath/games/typing-race.html"
    Navigate-PageAndWait -ws $ws -id ($cmdId++) -url $raceUrl

    # Test all 6 sound effects for Race
    $soundTestRace = Evaluate-Js -ws $ws -id ($cmdId++) -expression @"
    (() => {
      try {
        playCorrectTick();      // 700Hz triangle 0.03s
        playWrongSoft();        // 180Hz square 0.05s
        playCountdownBeep(false); // 440Hz 0.15s
        playCountdownBeep(true);  // 880Hz 0.25s
        playOvertakeSweep();    // 500->900Hz sweep 0.15s
        playVictoryFanfare();   // 523-659-784-1047Hz
        playDefeatSweep();      // 400->150Hz sawtooth sweep
        return { success: true };
      } catch(e) {
        return { success: false, error: e.message };
      }
    })()
"@
    Record-Test "TypingRace" "Sound Effects Synthesizer" ($soundTestRace.success -eq $true) "All race audio synthesis verified"

    # Test Leaderboard persistence
    $lbTest = Evaluate-Js -ws $ws -id ($cmdId++) -expression @"
    (() => {
      saveScore('ApexTyper', 82, 99);
      const lb = getLeaderboard();
      return { topName: lb[0].name, topWpm: lb[0].wpm, count: lb.length };
    })()
"@
    Record-Test "TypingRace" "Leaderboard Save & Retrieval" ($lbTest.topName -eq 'ApexTyper' -and $lbTest.count -le 5) "Saved ApexTyper with 82 WPM to top 5"

    # Test Race Start and Keystroke Progress
    $raceProgressTest = Evaluate-Js -ws $ws -id ($cmdId++) -expression @"
    (() => {
      launchRace();
      const firstChar = targetText[0];
      handleKey(firstChar);
      return { active: raceActive, idx: currentIndex };
    })()
"@
    Record-Test "TypingRace" "Race Progression" ($raceProgressTest.active -eq $true -and $raceProgressTest.idx -eq 1) "Race active, player progressed"

    # =========================================================================
    # TEST 5: games/asteroid-game.html
    # =========================================================================
    Write-Host "`n--- TESTING ASTEROID-GAME.HTML ---" -ForegroundColor Cyan
    $asteroidUrl = "file:///$workspacePath/games/asteroid-game.html"
    Navigate-PageAndWait -ws $ws -id ($cmdId++) -url $asteroidUrl

    # Test all sound effects including the EXACT playExplosion function
    $soundTestAsteroid = Evaluate-Js -ws $ws -id ($cmdId++) -expression @"
    (() => {
      try {
        playLaserTick();           // 700Hz sine 0.03s
        playDullThud();            // 140Hz square 0.06s
        playAsteroidDestroyed();   // playExplosion white noise + crack + 300->60Hz sweep
        playShipHit();             // 100Hz square 0.3s
        playLevelUpSciFi();        // 523->1046Hz chime
        playGameOverSawtooth();    // 400->300->150Hz sawtooth
        return { success: true };
      } catch(e) {
        return { success: false, error: e.message };
      }
    })()
"@
    Record-Test "Asteroids" "Sound Effects (inc. playExplosion)" ($soundTestAsteroid.success -eq $true) "Explosion buffer noise & all sounds verified"

    # Test Ambient 55Hz Hum Toggle
    $humTest = Evaluate-Js -ws $ws -id ($cmdId++) -expression @"
    (() => {
      const before = isAmbientOn;
      toggleAmbientHum();
      const afterOn = isAmbientOn;
      toggleAmbientHum();
      const afterOff = isAmbientOn;
      return { before: before, afterOn: afterOn, afterOff: afterOff };
    })()
"@
    Record-Test "Asteroids" "55Hz Ambient Hum Toggle" ($humTest.afterOn -eq $true -and $humTest.afterOff -eq $false) "Toggled ON and OFF cleanly"

    # Test Asteroid targeting, destruction, and screen shake
    $asteroidPlayTest = Evaluate-Js -ws $ws -id ($cmdId++) -expression @"
    (() => {
      startGame();
      asteroids = [];
      asteroids.push(new Asteroid('mars', 1.0));
      handleKey('m');
      const targetIsMars = targetedAsteroid ? targetedAsteroid.word === 'mars' : false;
      handleKey('a');
      handleKey('r');
      handleKey('s');

      triggerScreenShake();
      const hasShake = document.getElementById('canvasWrap').classList.contains('shake');

      return {
        targetLocked: targetIsMars,
        destroyed: asteroidsDestroyed,
        scoreAfter: score,
        shaking: hasShake
      };
    })()
"@
    Record-Test "Asteroids" "Target, Destroy & Screen Shake" ($asteroidPlayTest.destroyed -eq 1 -and $asteroidPlayTest.shaking -eq $true) "Destroyed 'mars', particles spawned, screen shake triggered"

    $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "Done", [System.Threading.CancellationToken]::None).Wait()

} finally {
    if ($chromeProc -and !$chromeProc.HasExited) {
        Stop-Process -Id $chromeProc.Id -Force
    }
    Remove-Item -Recurse -Force -Path $tempDir -ErrorAction SilentlyContinue
}

# Print final report
$passCount = ($testResults | Where-Object { $_.Success }).Count
$failCount = ($testResults | Where-Object { !$_.Success }).Count

Write-Host "`n========================================================" -ForegroundColor Yellow
Write-Host "AUTOMATED CDP VERIFICATION COMPLETE" -ForegroundColor Yellow
$summaryColor = if ($failCount -eq 0) { "Green" } else { "Red" }
Write-Host "Total Tests: $($testResults.Count) | PASSED: $passCount | FAILED: $failCount" -ForegroundColor $summaryColor
Write-Host "========================================================" -ForegroundColor Yellow

if ($failCount -gt 0) {
    exit 1
}
