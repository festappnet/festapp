
export const BlueprintConfig = {
    // Grid & Layout
    seatSize: 60,
    baseSize: 40, // Flutter reference size
    
    // Styling Defaults
    basePadding: 2.5,
    baseRadius: 8.0,
    
    // Interaction
    minScale: 0.1, // effectively calculated dynamic, but hard limit
    maxScale: 5,
    overscrollLimit: 150,
    tapThreshold: 10,
    panMargin: 24,

    // Animation
    snapAnimationDuration: 300,
    
    // Colors (can import from SeatWidgetHelper if needed, or define here)
    colors: {
        lessContrastyBlack: '#444444'
    }
};

export const SeatStates = {
    AVAILABLE: 'available',
    SELECTED_BY_ME: 'selected_by_me',
    SELECTED: 'selected',
    ORDERED: 'ordered',
    USED: 'used',
    TAKEN: 'taken',
    BLACK: 'black',
    EMPTY: 'empty'
};
