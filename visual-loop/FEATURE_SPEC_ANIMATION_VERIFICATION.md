# Feature Spec: Animation Verification via Screenshot Diff

## Overview

**Problem:** The current visual verification loop uses single static screenshots, which cannot verify animations. The vision model sees one frame and reports "no animation visible" even when CSS keyframes/transitions are correctly implemented.

**Current Workaround:** `--verify-code "pattern"` flag that greps for code patterns. Works but doesn't verify that animations actually render/run in the browser.

**Proposed Solution:** Screenshot diffing - capture two frames N seconds apart and use image comparison to detect motion. If pixel differences exceed a threshold, animation is confirmed running.

---

## Goals

1. **Verify animations actually run in browser** (not just that code exists)
2. **Work with both CSS and JavaScript animations** (keyframes, transitions, requestAnimationFrame, etc.)
3. **Maintain zero-dependency philosophy** (fallback gracefully if imagemagick unavailable)
4. **Minimal false positives/negatives** (distinguish animation from UI noise like loading spinners)
5. **Integrate cleanly** into existing auto.sh loop without breaking current workflows

---

## Core Approach

### High-Level Algorithm

1. Take first screenshot (baseline)
2. Wait N seconds (configurable interval based on expected animation duration)
3. Take second screenshot (comparison frame)
4. Compare images using ImageMagick's `compare` command
5. Parse difference metric (RMSE, pixel count, or percentage)
6. If difference > threshold → animation confirmed running
7. If difference ≈ 0 → static (animation broken/missing)

### Why ImageMagick?

- **Ubiquitous:** Pre-installed on most Linux systems, available via homebrew/apt
- **Battle-tested:** Industry standard for image manipulation
- **Flexible metrics:** Supports RMSE, AE (absolute error pixel count), percentage
- **One-liner usage:** Simple CLI interface

---

## Implementation Specification

### 1. New CLI Flag

```bash
./auto.sh "Add fade-in animation to title" --verify-animation
```

**Flag variants (pick one):**
- `--verify-animation` (recommended - explicit and clear)
- `--animation-check` (alternative)
- `--diff-check` (too vague)

**Flag behavior:**
- Mutually exclusive with `--verify-code` (pick one verification mode)
- Compatible with `--expect "text"` (quick pre-check can still run)
- Enables two-screenshot capture + diff analysis in verification loop

### 2. Configuration Parameters

**Environment Variables (overridable):**

```bash
# Interval between screenshots (milliseconds)
ANIMATION_INTERVAL="${ANIMATION_INTERVAL:-2000}"  # 2 seconds default

# Difference threshold (percentage of changed pixels)
ANIMATION_THRESHOLD="${ANIMATION_THRESHOLD:-0.5}"  # 0.5% pixels changed

# ImageMagick compare metric
ANIMATION_METRIC="${ANIMATION_METRIC:-AE}"  # Absolute Error (pixel count)
# Alternatives: RMSE (root mean square error), PAE (peak absolute error)

# Fuzz factor (tolerance for anti-aliasing/compression artifacts)
ANIMATION_FUZZ="${ANIMATION_FUZZ:-2%}"  # 2% color tolerance
```

**Rationale:**
- **2000ms interval:** Catches most CSS animations (typically 0.3s-3s). Long enough to span one cycle of looping animations.
- **0.5% threshold:** On 1280x720 (921,600 pixels), this is ~4,608 pixels. Filters out tiny UI noise (cursor blinks, timestamp updates) but catches meaningful animation.
- **AE metric:** Counts exact changed pixels. Simple, interpretable. RMSE considers magnitude of change (better for subtle fades).
- **2% fuzz:** Ignores minor compression artifacts, anti-aliasing differences between renders.

### 3. New Bash Functions

**Function: `take_animation_pair()`**

```bash
# Take two screenshots N milliseconds apart for diff analysis
# Args: $1=url, $2=output_base (e.g., "/tmp/anim"), $3=interval_ms
# Outputs: Writes ${output_base}_1.png and ${output_base}_2.png
# Returns: 0 on success, 1 on failure
take_animation_pair() {
    local url="$1"
    local output_base="$2"
    local interval_ms="${3:-$ANIMATION_INTERVAL}"

    local shot1="${output_base}_1.png"
    local shot2="${output_base}_2.png"

    log "${DIM}Taking baseline screenshot...${RESET}"
    take_screenshot "$shot1" || return 1

    log "${DIM}Waiting ${interval_ms}ms for animation...${RESET}"
    sleep "$(echo "scale=3; $interval_ms / 1000" | bc)"

    log "${DIM}Taking comparison screenshot...${RESET}"
    take_screenshot "$shot2" || return 1

    echo "$shot1 $shot2"
    return 0
}
```

**Function: `compare_screenshots()`**

```bash
# Compare two screenshots and return difference metric
# Args: $1=shot1, $2=shot2, $3=diff_output_path
# Outputs: Writes visual diff to $3 (optional debug artifact)
# Returns: Difference metric value (e.g., changed pixel count)
compare_screenshots() {
    local shot1="$1"
    local shot2="$2"
    local diff_out="$3"

    # Check imagemagick availability
    if ! command -v compare &>/dev/null; then
        log "${YELLOW}⚠ ImageMagick 'compare' not found - skipping diff check${RESET}"
        return 255  # Special code: dependency missing
    fi

    # Run compare with error metric
    # -metric AE = absolute error (changed pixel count)
    # -fuzz 2% = ignore minor color differences
    # diff_out = visual red-highlight PNG (debug artifact)
    local diff_value
    diff_value=$(compare \
        -metric "$ANIMATION_METRIC" \
        -fuzz "$ANIMATION_FUZZ" \
        "$shot1" "$shot2" "$diff_out" 2>&1 | grep -oE '[0-9.]+' || echo "0")

    echo "$diff_value"
    return 0
}
```

**Function: `verify_animation()`**

```bash
# Main animation verification logic
# Args: $1=output_base (for screenshot pair)
# Returns: 0 if animation detected, 1 if static, 255 if check unavailable
verify_animation() {
    local output_base="$1"
    local shot1="${output_base}_1.png"
    local shot2="${output_base}_2.png"
    local diff_out="${output_base}_diff.png"

    # Take screenshot pair
    take_animation_pair "$URL" "$output_base" "$ANIMATION_INTERVAL" || {
        log "${RED}Failed to capture screenshot pair${RESET}"
        return 1
    }

    # Compare
    local diff_value
    diff_value=$(compare_screenshots "$shot1" "$shot2" "$diff_out")
    local compare_status=$?

    if [[ $compare_status -eq 255 ]]; then
        log "${YELLOW}Animation check unavailable - falling back to code verification${RESET}"
        return 255  # Trigger fallback
    fi

    # Calculate total pixels for percentage
    local width height total_pixels
    width=$(identify -format "%w" "$shot1")
    height=$(identify -format "%h" "$shot1")
    total_pixels=$((width * height))

    # Calculate percentage changed
    local pct_changed
    pct_changed=$(echo "scale=2; 100 * $diff_value / $total_pixels" | bc)

    log "${DIM}Animation diff: ${diff_value} pixels changed (${pct_changed}% of ${total_pixels})${RESET}"
    log "${DIM}Diff visualization: $diff_out${RESET}"

    # Check threshold
    local threshold_pixels
    threshold_pixels=$(echo "$total_pixels * $ANIMATION_THRESHOLD / 100" | bc)

    if (( $(echo "$diff_value > $threshold_pixels" | bc -l) )); then
        log "${GREEN}✓ Animation detected: ${pct_changed}% pixels changed (threshold: ${ANIMATION_THRESHOLD}%)${RESET}"
        return 0
    else
        log "${RED}✗ No animation detected: ${pct_changed}% pixels changed (threshold: ${ANIMATION_THRESHOLD}%)${RESET}"
        return 1
    fi
}
```

### 4. Integration into auto.sh Main Loop

**Modifications to existing loop (around line 420-438):**

```bash
# Step 2: Animation verification mode
if [[ -n "$VERIFY_ANIMATION" ]]; then
    # Start dev server (animations need live app)
    stop_dev
    start_dev || { log "${RED}Failed to start dev server${RESET}"; restore_checkpoint; exit 1; }

    # Run animation check
    ANIM_BASE="$LOG_DIR/iter_${i}_anim"
    verify_animation "$ANIM_BASE"
    ANIM_STATUS=$?

    if [[ $ANIM_STATUS -eq 0 ]]; then
        # Animation verified - task complete
        log ""
        log "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
        log "${GREEN}${BOLD}  ✓ TASK COMPLETE (iteration $i) - animation verified${RESET}"
        log "${GREEN}${BOLD}════════════════════════════════════════════════════════════════${RESET}"
        log ""
        log "Session log: $LOG_DIR"
        print_metrics
        exit 0
    elif [[ $ANIM_STATUS -eq 255 ]]; then
        # Fallback to code verification if imagemagick unavailable
        log "${YELLOW}Falling back to code pattern verification${RESET}"
        if [[ -n "$VERIFY_CODE" ]] && verify_code_pattern; then
            log "${GREEN}✓ Code patterns found (fallback verification)${RESET}"
            exit 0
        fi
        FEEDBACK="ImageMagick unavailable and code patterns not found. Install imagemagick or set --verify-code fallback."
    else
        # No animation detected
        FEEDBACK="Animation not detected in ${ANIMATION_INTERVAL}ms interval. Check: (1) animation duration matches interval, (2) animation is actually running (inspect browser DevTools), (3) animation is visible in viewport."
    fi

    log ""
    log "${RED}Issues:${RESET} Animation verification failed"
    log "${YELLOW}Feedback for next iteration:${RESET} $FEEDBACK"
    log ""
    continue
fi

# Step 3: Code-only verification mode (existing logic)
if [[ -n "$VERIFY_CODE" ]]; then
    # ... existing code verification logic ...
fi
```

**New flag parsing (around line 26-36):**

```bash
VERIFY_ANIMATION=""

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --expect) EXPECT_TEXT="$2"; shift 2 ;;
        --verify-code) VERIFY_CODE="$2"; shift 2 ;;
        --verify-animation) VERIFY_ANIMATION="true"; shift ;;
        --context-files) CONTEXT_FILES="$2"; shift 2 ;;
        --no-stash) NO_STASH=true; shift ;;
        -*) shift ;;
        *) [[ -z "$TASK" ]] && TASK="$1"; shift ;;
    esac
done

# Validate flags
if [[ -n "$VERIFY_CODE" && -n "$VERIFY_ANIMATION" ]]; then
    echo "Error: Cannot use both --verify-code and --verify-animation"
    exit 1
fi
```

---

## Usage Examples

### Example 1: Basic CSS Keyframe Animation

```bash
./auto.sh "Add a pulsing glow animation to the title text" --verify-animation
```

**Expected behavior:**
1. AI adds CSS keyframe animation (e.g., `@keyframes pulse { ... }`)
2. auto.sh captures two screenshots 2s apart
3. ImageMagick detects ~15% pixel change (glowing halo expanding/contracting)
4. Verification passes → task complete

### Example 2: Subtle Fade-In (Adjust Interval)

```bash
ANIMATION_INTERVAL=5000 ./auto.sh "Add 3-second fade-in to modal" --verify-animation
```

**Why 5000ms?** 3s fade-in animation needs enough time to show visible change. Capture at t=0 (invisible) and t=5s (fully visible) shows maximum difference.

### Example 3: Rapid Animation (Lower Threshold)

```bash
ANIMATION_THRESHOLD=0.1 ./auto.sh "Add subtle hover ripple effect" --verify-animation
```

**Why 0.1%?** Subtle ripples may only change 0.2-0.5% of pixels. Lower threshold catches smaller animations.

### Example 4: Fallback to Code Verification

```bash
./auto.sh "Add rotation animation" --verify-animation --verify-code "@keyframes rotate"
```

**Fallback behavior:** If ImageMagick unavailable, falls back to grepping for `@keyframes rotate` in source.

---

## Edge Cases & Solutions

### 1. Looping Animations (Same Frame Captured Twice)

**Problem:** Animation loops every 2s. If we capture at t=0 and t=2s, we might catch the same frame twice.

**Solution 1 (Recommended):** Use non-integer intervals
```bash
ANIMATION_INTERVAL=1500  # Capture mid-cycle
```

**Solution 2:** Capture 3 frames, compare frame1 vs frame2 AND frame2 vs frame3. If either pair differs, animation exists.

```bash
# Pseudo-code for triple-capture (future enhancement)
take_screenshot frame1
sleep 0.7s
take_screenshot frame2
sleep 0.7s
take_screenshot frame3

diff1=$(compare frame1 frame2)
diff2=$(compare frame2 frame3)

if [[ $diff1 > threshold || $diff2 > threshold ]]; then
    animation_detected=true
fi
```

### 2. One-Shot Animations (Only Plays Once on Load)

**Problem:** Fade-in plays once on page load. If we capture at t=0 (animation started) and t=2s (animation finished), we'll catch difference. But on second iteration, animation is done and won't replay.

**Solution:** Hard-reload page before each screenshot pair

```bash
take_animation_pair() {
    # Force full page reload (not cached)
    "$CHROMIUM" --headless --disable-gpu --screenshot="$shot1" \
        --window-size="$WINDOW_SIZE" \
        --disable-cache \
        "$URL?nocache=$(date +%s)" 2>/dev/null

    sleep "$interval"

    # Second screenshot from same fresh page (won't reload)
    # ... existing logic ...
}
```

**Better Solution:** Add cache-busting query param + localStorage clear:

```bash
# Before first screenshot
"$CHROMIUM" --headless --user-data-dir=/tmp/chrome-temp-$$ --screenshot="$shot1" "$URL" 2>/dev/null
# Chromium instance exits, clears state
# Before second screenshot (new instance, fresh state)
"$CHROMIUM" --headless --user-data-dir=/tmp/chrome-temp-$$-2 --screenshot="$shot2" "$URL" 2>/dev/null
```

### 3. Too-Fast Animations (<100ms)

**Problem:** Animation completes in 0.2s. Capturing at t=0 and t=2s shows same final state.

**Solution:**
- User must set `ANIMATION_INTERVAL=200` (match animation duration)
- OR: Auto-detect animation duration from CSS and adjust interval dynamically (advanced, future enhancement)

**Best Practice Guidance in Docs:**
> For animations <1s duration, set `ANIMATION_INTERVAL` to match animation cycle time. Example: 500ms animation → `ANIMATION_INTERVAL=500`

### 4. Multiple Animations on Screen

**Problem:** Testing fade-in animation on modal, but background has unrelated loading spinner. Diff detects spinner motion, reports "animation exists" even though modal fade-in is broken.

**Solutions:**

**Option A (Simple):** Region-of-Interest (ROI) masking via ImageMagick
```bash
# Only compare pixels in top-left 640x360 quadrant (where modal appears)
compare -metric AE -fuzz 2% \
    -crop 640x360+0+0 \  # Crop both images to same ROI
    "$shot1" "$shot2" "$diff_out"
```

**Option B (Future Enhancement):** Element-specific screenshots
```bash
# Capture only .modal element using Puppeteer-style element selector
# Requires switching from headless Chrome to Puppeteer/Playwright
```

**Recommended for MVP:** Document ROI cropping but don't auto-implement. Let users manually test with full-screen diff first.

### 5. Animations Only on Hover/Interaction

**Problem:** Button hover animation requires mouse interaction.

**Solution:** Pre-trigger via URL hash or localStorage flag

```bash
# Example: App checks for ?test-hover and auto-applies hover state
take_screenshot "$URL?test-hover=true"
```

**Alternative:** Use Puppeteer for interaction (future enhancement, out-of-scope for ImageMagick MVP)

---

## Threshold Tuning Guidelines

### Recommended Thresholds by Animation Type

| Animation Type | RMSE Threshold | AE Threshold (%) | Reasoning |
|----------------|----------------|-------------------|-----------|
| Large motion (slide-in, rotate) | 500-1000 | 2-5% | Significant pixel change |
| Medium motion (fade, pulse) | 200-500 | 0.5-2% | Moderate pixel change |
| Subtle (shadows, glows) | 50-200 | 0.1-0.5% | Small pixel change |
| Micro-interactions (ripples) | 10-50 | 0.05-0.1% | Minimal pixel change |

### Noise Baseline (Static Page)

**Test methodology:**
```bash
# Capture two screenshots of completely static page
take_screenshot /tmp/static1.png
sleep 2
take_screenshot /tmp/static2.png
compare -metric AE /tmp/static1.png /tmp/static2.png /tmp/diff.png
```

**Expected noise sources:**
- Chrome rendering non-determinism (~0-10 pixels on 1280x720)
- Anti-aliasing differences
- Timestamp updates (if visible on page)
- Network loading indicators

**Calibration:** Set threshold 10x above measured static noise. If static pages show 5 pixel diff, use threshold of 50+ pixels.

---

## Fallback Strategy

### Dependency Check

```bash
check_imagemagick() {
    if command -v compare &>/dev/null && command -v identify &>/dev/null; then
        log "${GREEN}✓ ImageMagick detected${RESET}"
        return 0
    else
        log "${YELLOW}⚠ ImageMagick not found${RESET}"
        log "${DIM}Install: sudo apt install imagemagick  (Ubuntu/Debian)${RESET}"
        log "${DIM}Install: brew install imagemagick  (macOS)${RESET}"
        return 1
    fi
}
```

### Graceful Degradation

**Priority order:**
1. **Best:** ImageMagick diff (ground truth - animation actually running)
2. **Good:** Code pattern verification (verifies code exists, not runtime behavior)
3. **Minimal:** Quick text check (verifies string exists in source)
4. **Last Resort:** Skip animation check, warn user

```bash
if [[ -n "$VERIFY_ANIMATION" ]]; then
    if check_imagemagick; then
        verify_animation "$ANIM_BASE" || {
            FEEDBACK="Animation diff failed. See $LOG_DIR/iter_${i}_diff.png for visual comparison."
        }
    elif [[ -n "$VERIFY_CODE" ]]; then
        log "${YELLOW}Falling back to code verification (ImageMagick unavailable)${RESET}"
        verify_code_pattern || {
            FEEDBACK="Code patterns not found: $VERIFY_CODE"
        }
    else
        log "${RED}Cannot verify animation: ImageMagick unavailable and no --verify-code fallback set${RESET}"
        FEEDBACK="Install ImageMagick or provide --verify-code fallback pattern"
        exit 1
    fi
fi
```

---

## AI Feedback Integration

### What to Tell AI When Animation Check Fails

**Current feedback (code verification):**
```
FEEDBACK="Code patterns not found. Required: $VERIFY_CODE"
```

**New feedback (animation verification):**
```
FEEDBACK="Animation not detected: ${pct_changed}% pixel difference (threshold: ${ANIMATION_THRESHOLD}%).

Possible causes:
1. Animation duration mismatch: Set ANIMATION_INTERVAL=${ANIMATION_INTERVAL}ms to match your animation's cycle time
2. Animation not visible: Check element is in viewport and not display:none
3. Animation not running: Verify animation-play-state is 'running', not 'paused'
4. CSS not applied: Check class/ID selectors are correct
5. Wrong element animated: Verify animation applies to intended element

Debug artifacts:
- Frame 1: $shot1
- Frame 2: $shot2
- Visual diff: $diff_out (red pixels = changed areas)

Next iteration should:
- Check browser console for errors
- Verify animation properties (duration, timing-function, iteration-count)
- Ensure animation triggers on page load (not on hover/click)"
```

**Why detailed feedback?** Helps AI self-correct without human intervention. Rich context → better fixes.

---

## Command Reference

### ImageMagick Commands Used

**1. Compare two images:**
```bash
compare -metric AE -fuzz 2% image1.png image2.png diff.png
# Output (stderr): "4583" (pixel count)
# Writes: diff.png (visual red-highlight of changes)
```

**2. Get image dimensions:**
```bash
identify -format "%w %h" image.png
# Output (stdout): "1280 720"
```

**3. Calculate RMSE instead of pixel count:**
```bash
compare -metric RMSE -fuzz 2% image1.png image2.png diff.png
# Output: "45.2 (0.0123)" where 0.0123 is normalized RMSE
```

**4. Region-of-interest comparison:**
```bash
compare -metric AE -fuzz 2% \
    image1.png[640x360+0+0] \
    image2.png[640x360+0+0] \
    diff.png
# Only compares top-left 640x360 region
```

### Bash Arithmetic for Threshold Checks

**Calculate percentage:**
```bash
pct=$(echo "scale=2; 100 * $changed_pixels / $total_pixels" | bc)
# Example: scale=2 gives 2 decimal places
```

**Compare floats:**
```bash
if (( $(echo "$pct > $threshold" | bc -l) )); then
    echo "Threshold exceeded"
fi
```

**Sleep with fractional seconds:**
```bash
sleep 0.5  # 500ms
sleep $(echo "scale=3; 2000 / 1000" | bc)  # Convert ms to seconds
```

---

## Testing the Feature

### Manual Test: Verify True Positive

1. Create test animation:
```css
@keyframes pulse {
    0%, 100% { transform: scale(1); }
    50% { transform: scale(1.1); }
}
.title { animation: pulse 2s infinite; }
```

2. Run verification:
```bash
./auto.sh "Add pulsing animation to title" --verify-animation
```

3. Expected:
   - Iteration 1: AI adds animation CSS
   - Screenshots captured 2s apart
   - Diff shows ~5-10% pixel change (title scaling)
   - Verification passes

### Manual Test: Verify True Negative

1. Create static CSS:
```css
.title { color: red; }  /* No animation */
```

2. Run verification:
```bash
./auto.sh "Add pulsing animation to title" --verify-animation
```

3. Expected:
   - Screenshots show 0% change
   - Verification fails
   - AI receives feedback: "Animation not detected"
   - Iteration 2: AI tries again

### Manual Test: Fallback Behavior

1. Uninstall ImageMagick:
```bash
sudo apt remove imagemagick  # Temporarily
```

2. Run with fallback:
```bash
./auto.sh "Add rotation" --verify-animation --verify-code "@keyframes"
```

3. Expected:
   - ImageMagick check fails
   - Falls back to code verification
   - Greps for "@keyframes" in src/
   - Passes if pattern found

---

## Future Enhancements (Out of Scope for MVP)

### 1. Auto-Detect Animation Duration from CSS

Parse CSS `animation-duration` and auto-set `ANIMATION_INTERVAL`:

```bash
# Grep for animation-duration in relevant files
duration=$(grep -oP 'animation-duration:\s*\K[\d.]+s' src/components/Title.css)
interval_ms=$(echo "$duration * 1000" | bc)
```

### 2. Perceptual Diff (Not Just Pixel Count)

Use `perceptualdiff` tool instead of ImageMagick for better human-perception matching:
```bash
perceptualdiff image1.png image2.png -output diff.png
```

### 3. Video Recording Instead of Screenshots

Capture 2s video, extract frames, analyze frame-by-frame variance:
```bash
chromium --headless --video-output=out.webm --run-for=2s "$URL"
ffmpeg -i out.webm -vf fps=10 frames/frame_%03d.png
# Analyze variance across frames
```

### 4. Puppeteer Integration for Interaction

Trigger hover/click animations:
```javascript
// test-animation.js
const puppeteer = require('puppeteer');
const browser = await puppeteer.launch();
const page = await browser.newPage();
await page.goto('http://localhost:5173');
await page.screenshot({path: 'before.png'});
await page.hover('.button');  // Trigger hover animation
await page.waitForTimeout(500);
await page.screenshot({path: 'after.png'});
```

---

## Documentation & Error Messages

### Help Text Addition

```bash
# auto.sh usage (line 38)
[[ -n "$TASK" ]] || {
    echo "Usage: ./auto.sh \"task description\" [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --context-files \"A.tsx,B.css\"  Manually specify files (overrides auto-detect)"
    echo "  --expect \"text\"                Quick grep check before vision"
    echo "  --verify-code \"pattern\"        Code-only verification (grep for regex pattern)"
    echo "  --verify-animation             Screenshot diff verification (detects motion)"
    echo "  --no-stash                     Skip git checkpoint"
    echo ""
    echo "Environment Variables:"
    echo "  ANIMATION_INTERVAL=2000        Time between screenshots (ms) for animation check"
    echo "  ANIMATION_THRESHOLD=0.5        Min % pixel change to confirm animation"
    echo "  ANIMATION_METRIC=AE            ImageMagick metric (AE=pixel count, RMSE=error)"
    echo "  ANIMATION_FUZZ=2%              Color tolerance (ignore compression artifacts)"
    echo ""
    echo "Examples:"
    echo "  ./auto.sh \"Add fade-in to modal\" --verify-animation"
    echo "  ANIMATION_INTERVAL=500 ./auto.sh \"Add 0.5s hover effect\" --verify-animation"
    exit 1
}
```

### Error Messages

**ImageMagick not installed:**
```
⚠ ImageMagick not found - animation verification unavailable
Install: sudo apt install imagemagick  (Ubuntu/Debian)
         brew install imagemagick  (macOS)

Falling back to code verification. Use --verify-code "pattern" for fallback.
```

**Threshold too strict (no animations pass):**
```
✗ No animation detected: 0.3% pixels changed (threshold: 0.5%)

Hint: Animation might be too subtle. Try lowering threshold:
    ANIMATION_THRESHOLD=0.1 ./auto.sh "..." --verify-animation
```

**Interval too short (missed animation):**
```
✗ No animation detected: 0.01% pixels changed (threshold: 0.5%)

Hint: Animation duration might exceed capture interval.
Animation takes 5s to complete but ANIMATION_INTERVAL=2000ms.
Try: ANIMATION_INTERVAL=5000 ./auto.sh "..." --verify-animation
```

---

## Success Criteria

### MVP is Complete When:

1. **Core functionality works:**
   - [ ] `--verify-animation` flag captured and parsed
   - [ ] Two screenshots taken N seconds apart
   - [ ] ImageMagick compares screenshots
   - [ ] Threshold check passes/fails correctly
   - [ ] Task completes on animation verified

2. **Edge cases handled:**
   - [ ] ImageMagick unavailable → graceful fallback
   - [ ] Static page (noise baseline) → correctly fails
   - [ ] Looping animation → correctly detects motion
   - [ ] Non-integer intervals supported

3. **Integration clean:**
   - [ ] Works alongside existing `--verify-code` (mutually exclusive)
   - [ ] Works with `--expect` quick check
   - [ ] Logs clearly indicate diff results
   - [ ] Diff artifacts saved to `$LOG_DIR` for debugging

4. **Documentation complete:**
   - [ ] Help text updated
   - [ ] README examples added
   - [ ] Error messages actionable
   - [ ] Threshold tuning guide included

---

## Open Questions

1. **Should we support `--verify-animation=<interval>`?**
   - Example: `--verify-animation=3000` (inline interval override)
   - Pro: Cleaner than env var
   - Con: Another syntax variant

2. **Should diff.png always be saved, or only on failure?**
   - Always: Helps debugging passes too (verify it caught the right motion)
   - On failure: Saves disk space
   - Recommendation: Always save to `$LOG_DIR`, include in metrics

3. **Should we integrate with analyze.sh (vision model)?**
   - Vision model could analyze diff.png: "Red pixels indicate title text scaling animation"
   - Pro: Richer feedback to AI
   - Con: More expensive, slower
   - Recommendation: Phase 2 enhancement

4. **Metric preference: AE (pixel count) or RMSE (error magnitude)?**
   - AE: Simple, interpretable (e.g., "5000 pixels changed")
   - RMSE: Better for subtle changes (e.g., "fade from 0 to 0.5 opacity")
   - Recommendation: Default AE, allow override via `ANIMATION_METRIC=RMSE`

---

## Summary

This spec proposes a robust, maintainable screenshot-diff solution for animation verification in the autonomous dev loop. Key design decisions:

- **Simple dependency:** ImageMagick (ubiquitous, battle-tested)
- **Graceful degradation:** Falls back to code verification if unavailable
- **Tunable:** Interval, threshold, metric all configurable via env vars
- **Debuggable:** Saves frame1, frame2, diff.png for manual inspection
- **Actionable feedback:** Detailed error messages guide AI to fix

The feature is scoped to be implementable in <200 LOC, integrates cleanly into existing loop, and solves the core problem: **verifying animations actually run, not just that code exists**.
