import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const rendererMatch = html.match(/function drawStrokes\(canvas, strokes = \[\]\) \{[\s\S]*?(?=\n    function shapeBounds\()/);
assert.ok(rendererMatch, 'the web drawing renderer is present');

const drawContext = vm.createContext({ clamp: (value, min = 0, max = 1) => Math.min(max, Math.max(min, value)) });
vm.runInContext(`${rendererMatch[0]}; this.drawStrokes = drawStrokes;`, drawContext);

function renderOne(stroke) {
  const calls = [];
  const context = {
    clearRect: (...args) => calls.push(['clearRect', ...args]),
    save: () => calls.push(['save']),
    restore: () => calls.push(['restore']),
    beginPath: () => calls.push(['beginPath']),
    moveTo: (...args) => calls.push(['moveTo', ...args]),
    lineTo: (...args) => calls.push(['lineTo', ...args]),
    quadraticCurveTo: (...args) => calls.push(['quadraticCurveTo', ...args]),
    stroke: () => calls.push(['stroke'])
  };
  const canvas = { clientWidth: 100, clientHeight: 100, width: 200, height: 200, getContext: () => context };
  drawContext.drawStrokes(canvas, [stroke]);
  return { calls, context };
}

test('freehand strokes use curved interpolation and preserve round joins', () => {
  const { calls, context } = renderOne({
    tool: 'pen', size: 3,
    points: [{ x: .1, y: .1 }, { x: .25, y: .4 }, { x: .5, y: .2 }, { x: .8, y: .7 }]
  });
  assert.ok(calls.some(([name]) => name === 'quadraticCurveTo'), 'curves interpolate between pointer samples');
  assert.equal(context.lineCap, 'round');
  assert.equal(context.lineJoin, 'round');
});

test('highlighter strokes keep rounded ends and joins', () => {
  const { context } = renderOne({
    tool: 'highlighter', size: 4,
    points: [{ x: .1, y: .5 }, { x: .5, y: .3 }, { x: .9, y: .5 }]
  });
  assert.equal(context.lineCap, 'round');
  assert.equal(context.lineJoin, 'round');
});

test('pen pressure changes stroke width while older points keep the normal baseline', () => {
  const light = renderOne({ tool: 'pen', size: 4, points: [{ x: .1, y: .2, pressure: .1 }, { x: .8, y: .7, pressure: .1 }] });
  const firm = renderOne({ tool: 'pen', size: 4, points: [{ x: .1, y: .2, pressure: .9 }, { x: .8, y: .7, pressure: .9 }] });
  const legacy = renderOne({ tool: 'pen', size: 4, points: [{ x: .1, y: .2 }, { x: .8, y: .7 }] });
  assert.ok(firm.context.lineWidth > legacy.context.lineWidth);
  assert.ok(legacy.context.lineWidth > light.context.lineWidth);
});
