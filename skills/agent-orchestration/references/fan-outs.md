# Fan-outs

## Verification fan-outs are capped and staged

Cap findings before verifying (`review.findings.slice(0, 5)`), and never run byte-identical duplicate skeptics in parallel — sampling noise is not verification. Run one skeptic; spend a second only on findings the first FAILED to refute:

```js
const v1 = await agent(refute(f), { ...SMART, schema: VERDICT });
const v2 = v1.refuted ? null : await agent(refute(f), { ...SMART, schema: VERDICT });
const survives = !v1.refuted && v2 && !v2.refuted;
```

## Cheap swarms are for grounded breadth; judgment stays smart

- A wide `sonnet`/`haiku` fan-out is right when every claim can carry its own evidence — file:line, a verbatim quote, a command that proves it (call-site sweeps, checklist audits, per-file conformance checks, log characterization).
- It is wrong for subtle analysis: one smart-model read beats ten cheap ones.
- Anti-hallucination machinery that verifiably works: schema output with "empty is a valid answer — never invent to fill a quota", verbatim-evidence fields re-checked at verify time, refute-by-default skeptics (the staged v1/v2 above — cheap v1 first).
- Prefer deterministic checks (a test run cannot hallucinate) over any model vote; stop fan-outs on marginal yield (2 dry rounds), never at a fixed headcount.
- NO chatty multi-turn mutual checking between agents — it multiplies boot cost (the swarm's real cost floor) without adding ground truth.
- Shape: find (cheap, evidence-carrying) → verify (staged skeptics) → synthesize (smart), as a DAG.
