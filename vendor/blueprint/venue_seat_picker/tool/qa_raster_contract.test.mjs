import test from 'node:test';
import assert from 'node:assert/strict';
import {classifyRaster} from './qa_raster_contract.mjs';
const frame = () => ({name:'frame',masks:[{minX:1,minY:1,maxX:10,maxY:10},{minX:1,minY:1,maxX:10,maxY:10}],
  registrationInk:[{mass:1,centroid:[5,5]},{mass:1,centroid:[5,5]}],interiorDifferences:100,variablePaintInteriorDifferences:90,
  otherInteriorDifferences:10,otherInteriorFringe:10,maxOtherChannelDelta:1,maxVariablePaintChannelDelta:1});
test('complete gradient and fringe counts classify more than 32 diagnostic samples', () => {
  assert.equal(classifyRaster(frame()).accepted,true);
});
test('registration, missing accounting and larger color differences remain failures', () => {
  for(const patch of [{maxVariablePaintChannelDelta:2},{maxOtherChannelDelta:2},{otherInteriorFringe:9},
    {interiorDifferences:101},{registrationInk:[{mass:0,centroid:[0,0]},{mass:0,centroid:[0,0]}]},{registrationInk:[{mass:1,centroid:[5,5]},{mass:1,centroid:[6,5]}]},
    {masks:[{minX:1},{minX:2}]}]) assert.equal(classifyRaster({...frame(),...patch}).accepted,false,JSON.stringify(patch));
});
