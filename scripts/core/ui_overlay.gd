extends CanvasLayer
## Persistent UI overlay layer that sits above the active screen.
##
## Hosts always-on developer UI (the debug overlay) at bootstrap. Production
## HUD/dialog surfaces are added in later milestones; this keeps them decoupled
## from any individual screen.
