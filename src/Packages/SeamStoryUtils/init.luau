--[=[
    Utilities for hooking up Seam to UI Labs for UI stories.

    @class SeamStoryUtils
]=]

local SeamStoryUtils = {}

--Types
type BaseState<T> = {
    Value : T,
}

type ValueInstance<T> = {
    Changed : RBXScriptSignal,
} & BaseState<T>

type SpringInstance<T> = {
    Velocity : T,
    Target : T
} & BaseState<T>

type TweenInstance<T> = {
    Target : T
} & BaseState<T>

type RenderedInstance<T> = {} & BaseState<T>
type ComputedInstance<T> = {} & BaseState<T>
type ForPairsInstance<T> = {} & BaseState<T>

type ScopeInstance = {
    New : (self : ScopeInstance, Class : string | Instance | {[string] : any?}, Properties : {[any] : any}, From : any?) -> Instance,
    Rendered : (self : ScopeInstance, Callback : (number) -> any?) -> RenderedInstance<any>,
    Value : (self : ScopeInstance, InitialValue : any) -> ValueInstance<any>,
    Spring : (self : ScopeInstance, Value : BaseState<any> | any, Speed : number, Dampening : number) -> SpringInstance<any>,
    Tween : (self : ScopeInstance, Value : BaseState<any> | any, TweenInformation : TweenInfo) -> TweenInstance<any>,
    Computed : (self : ScopeInstance, Callback : ((Value : ValueInstance<any>) -> any) -> any?) -> ComputedInstance<any>,
    ForPairs : (self : ScopeInstance, TrackedValue : ValueInstance<any>, Callback : ((Value : ValueInstance<any>) -> any) -> any?) -> ForPairsInstance<any>,
    OnChanged : (self : ScopeInstance, Object : any, Callback : (PropertyChanged : string, NewValue : any) -> nil) -> RBXScriptConnection,
    OnAttributeChanged : (self : ScopeInstance, AttributeName : string) -> (...any) -> RBXScriptConnection,
    OnEvent : (self : ScopeInstance, EventName : string) -> (...any) -> RBXScriptConnection,
    OnAttached : (self : ScopeInstance, Object : any, Callback : (AttachedInstance : Instance) -> nil) -> RBXScriptConnection,

    InnerScope : (self : ScopeInstance, ScopedObjects : {[string] : any}?) -> ScopeInstance,
    AddObject : <T>(self : ScopeInstance, Object : T) -> (T),
    RemoveObject : (self : ScopeInstance, Object : any) -> (),
    Destroy : (self : ScopeInstance) -> (),
}

--[=[
    Returns reactive Seam value states based on the generic controls of a UI labs story.

    @param Scope Scope -- The Seam scope
    @param Props {[any] : any} -- The `props` table passed into the generic story
    @return {[string] : ValueInstance<any>} -- The dictionary of controls mapped to value states
]=]

function SeamStoryUtils.GetValuesFromControls(Scope : ScopeInstance, Props : {[any] : any}) : {[string] : ValueInstance<any>}
    if not Scope then
        error("Scope required to get values from controls")
    end

    local Values : {[string] : ValueInstance<any>} = {}

    for Index, ControlValue in Props.controls do
        Values[Index] = Scope:Value(ControlValue)
    end

    local Unsubscribe = Props.subscribe(function(_, Data)
        for Index, Info in Data do
            if not Values[Index] then
                continue
            end

            if Info.__new ~= Info.__old then
                Values[Index].Value = Info.__new 
            end
        end
    end)

    Scope:AddObject(Unsubscribe)

    return Values
end

--[=[
    Returns a function that cleans up the scope

    @param Scope Scope -- The Seam scope
    @return () -> () -- The wrapped cleanup function
]=]

function SeamStoryUtils.WrappedScopeCleanup(Scope : ScopeInstance) : () -> ()
    return function()
        Scope:Destroy()
    end
end

return SeamStoryUtils