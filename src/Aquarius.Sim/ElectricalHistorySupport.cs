namespace Aquarius.Sim;

public sealed partial class ElectricalSimulation
{
    /// <summary>
    /// Establish a declared, per-battery initial charge at the start of a history.
    /// This does not infer usable reserve, prior delivered charge or battery health.
    /// Every battery must be specified, and all validation precedes mutation.
    /// </summary>
    public void SetInitialBatteryRemainingAh(IReadOnlyDictionary<string, double> remainingAh)
    {
        ArgumentNullException.ThrowIfNull(remainingAh);
        if (ticks != 0 || remainder != 0 ||
            batteries.Values.Any(b => b.ConsumedAh != 0 || b.ConsumedWh != 0))
            throw new InvalidOperationException("Initial battery charge can only be set before history time or consumption advances.");
        if (!remainingAh.Keys.ToHashSet(StringComparer.Ordinal).SetEquals(batteries.Keys))
            throw new ArgumentException("Initial battery charge must specify every battery exactly once.", nameof(remainingAh));
        var staged = new Dictionary<string, double>(StringComparer.Ordinal);
        foreach (var b in definition.Batteries)
        {
            var value = remainingAh[b.Id];
            if (!double.IsFinite(value) || value < 0 || value > b.CapacityAh)
                throw new ArgumentOutOfRangeException(nameof(remainingAh), $"Initial charge is outside the rated capacity of {b.Id}.");
            staged.Add(b.Id, value);
        }
        foreach (var b in staged) batteries[b.Key].RemainingAh = b.Value;
        initialTotalAh = staged.Values.Sum();
        RefreshAlarmAcknowledgements();
    }

    /// <summary>
    /// Advance an electrical-only history with unchanged external inputs. The same
    /// fixed-tick protection and depletion rules apply as in FixedStep. Stable ticks
    /// may be integrated together while their source currents and topology remain
    /// constant; ticks containing protection changes or source exhaustion are kept
    /// separate. Summation order can differ at floating-point rounding precision.
    /// Callers must stop at every external switch, export or fault event.
    /// </summary>
    public void AdvanceStableHistory(double seconds)
    {
        if (seconds < 0 || !double.IsFinite(seconds) || seconds > 86400)
            throw new ArgumentOutOfRangeException(nameof(seconds), "Step must be finite and at most one day.");
        remainder += seconds;
        var step = definition.FixedStepSeconds;
        while (remainder + 1e-12 >= step)
        {
            var pendingTicks = (long)Math.Floor((remainder + 1e-12) / step);
            var spanTicks = pendingTicks;
            var network = Solve();
            var protectionPending = definition.Breakers.Any(b =>
                b.RatedCurrentA is double rating && network.BranchCurrent.GetValueOrDefault(b.ControlId) > rating);
            if (protectionPending) spanTicks = 1;
            else
            {
                foreach (var source in network.BatteryCurrent)
                {
                    if (source.Value <= 0) continue;
                    // Leave an ordinary tick before every exhaustion boundary,
                    // including the solver's small empty-source threshold. If
                    // depletion changes voltage/current during that tick, a new
                    // overload is assessed at the following fixed tick as usual.
                    var untilEmptyTicks = Math.Max(0, batteries[source.Key].RemainingAh - 1e-12) * 3600 / source.Value / step;
                    if (untilEmptyTicks <= spanTicks)
                        spanTicks = Math.Max(1, (long)Math.Floor(untilEmptyTicks) - 1);
                }
            }
            var duration = spanTicks * step;
            Integrate(duration);
            remainder -= duration;
            if (remainder < 0 && remainder > -1e-10) remainder = 0;
            ticks += spanTicks;
        }
    }
}
