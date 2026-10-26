import { BlueprintLayoutAdapter } from './blueprint_layout_adapter.js';

/** Public geometry is consumed exclusively by the shared layout package. */
export class BlueprintDataPreparer {
    static prepareLayout(data, options) {
        return new BlueprintLayoutAdapter(data, options);
    }
}
