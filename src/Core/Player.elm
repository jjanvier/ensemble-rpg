module Core.Player exposing (..)

import AssocList as Dict exposing (Dict)
import Core.Level exposing (..)
import Core.PlayerIdentity.PlayerId as PlayerId exposing (..)
import Core.PlayerIdentity.PlayerName
import Core.Role exposing (Role)
import Core.RoleCard as RoleCard exposing (RoleCard)
import Core.XpProgress exposing (XpProgress, completed)
import Js.DecoderExtra exposing (firstCharDecoder)
import Json.Decode
import Json.Decode.Pipeline exposing (required, requiredAt)
import Json.Encode
import Random
import Random.Char



-- Identity


type alias PlayerIdentity =
    { id : PlayerId
    , icon : Char
    , name : String
    }


encodeIdentity : PlayerIdentity -> Json.Encode.Value
encodeIdentity identity =
    Json.Encode.object
        [ ( "icon", Json.Encode.string <| String.fromChar identity.icon )
        , ( "name", Json.Encode.string identity.name )
        , ( "id", PlayerId.encode identity.id )
        ]


identityDecoder : Json.Decode.Decoder PlayerIdentity
identityDecoder =
    Json.Decode.succeed PlayerIdentity
        |> required "id" (Json.Decode.string |> Json.Decode.map PlayerId)
        |> required "icon" firstCharDecoder
        |> required "name" Json.Decode.string



-- Model


type alias Player =
    { identity : PlayerIdentity
    , completedRoles : Dict Role ()
    , xp : Dict Role XpProgress
    }



-- Factory


fromIdentity : PlayerIdentity -> Player
fromIdentity identity =
    { identity = identity
    , completedRoles = Dict.empty
    , xp = Dict.empty
    }


unknown : Player
unknown =
    Player unknownIdentity Dict.empty Dict.empty


unknownIdentity : PlayerIdentity
unknownIdentity =
    { id = PlayerId "???", icon = 'U', name = "Unknown" }



-- Generator


generator : Random.Generator ( Player, Event )
generator =
    Random.map (Tuple.mapFirst fromIdentity) playerIdentityGenerator


playerIdentityGenerator : Random.Generator ( PlayerIdentity, Event )
playerIdentityGenerator =
    Random.map3
        PlayerIdentity
        PlayerId.generator
        Random.Char.emoticon
        Core.PlayerIdentity.PlayerName.generator
        |> Random.map (\identity -> ( identity, ChangedIdentity identity ))



-- Event


type Event
    = ChangedIdentity PlayerIdentity
    | DisplayedBehaviour Role


encodeEvent : Event -> Json.Encode.Value
encodeEvent event =
    case event of
        ChangedIdentity identity ->
            Json.Encode.object
                [ ( "type", Json.Encode.string "ChangedIdentity" )
                , ( "data"
                  , Json.Encode.object
                        [ ( "id", PlayerId.encode identity.id )
                        , ( "icon", Json.Encode.string <| String.fromChar identity.icon )
                        , ( "name", Json.Encode.string identity.name )
                        ]
                  )
                ]

        DisplayedBehaviour role ->
            Json.Encode.object
                [ ( "type", Json.Encode.string "DisplayedBehaviour" )
                , ( "data", RoleCard.encode role )
                ]


eventDecoder : Json.Decode.Decoder Event
eventDecoder =
    Json.Decode.field "type" Json.Decode.string
        |> Json.Decode.andThen
            (\eventName ->
                case eventName of
                    "ChangedIdentity" ->
                        Json.Decode.succeed PlayerIdentity
                            |> requiredAt [ "data", "id" ] PlayerId.decoder
                            |> requiredAt [ "data", "icon" ] firstCharDecoder
                            |> requiredAt [ "data", "name" ] Json.Decode.string
                            |> Json.Decode.map ChangedIdentity

                    "DisplayedBehaviour" ->
                        Json.Decode.succeed DisplayedBehaviour
                            |> required "data" RoleCard.decoder

                    _ ->
                        Json.Decode.fail <| "This is an unknown event: " ++ eventName
            )



-- Rest


reset : Player -> Player
reset player =
    { player | completedRoles = Dict.empty, xp = Dict.empty }


evolve : Event -> Player -> Player
evolve event player =
    case event of
        ChangedIdentity identity ->
            { player | identity = identity }

        DisplayedBehaviour role ->
            let
                progress =
                    progressOf role player |> Core.XpProgress.increment
            in
            { player
                | xp = Dict.insert role progress player.xp
                , completedRoles =
                    if Core.XpProgress.completed progress then
                        Dict.insert role () player.completedRoles

                    else
                        player.completedRoles
            }



-- Functions


progressOf : Role -> Player -> XpProgress
progressOf target player =
    player.xp
        |> Dict.get target
        |> Maybe.withDefault (Core.XpProgress.empty target)


numberOfBadgesWon : Player -> Int
numberOfBadgesWon player =
    List.length <| completedRoleCards player


completedRoleCards : Player -> List (RoleCard msg)
completedRoleCards player =
    player.completedRoles |> Dict.keys |> List.map RoleCard.fromRole


accessibleLevels : Player -> { levels : List Level, nextLevelRule : Maybe String }
accessibleLevels player =
    let
        accessible =
            all
                |> List.filter (isLevelAccessibleTo player)
    in
    { levels = accessible
    , nextLevelRule = nextLevelRule accessible
    }


nextLevelRule : List Level -> Maybe String
nextLevelRule levels =
    case levels |> List.sortBy Core.Level.toString |> List.reverse |> List.head of
        Just Level3 ->
            Just "Complete two level 3 roles to unlock level 4 roles"

        Just Level2 ->
            Just "Complete two level 2 roles to unlock level 3 roles"

        Just Level1 ->
            Just "Complete one role to unlock level 2 roles"

        _ ->
            Nothing


isLevelAccessibleTo : Player -> Level -> Bool
isLevelAccessibleTo player level =
    case level of
        Level1 ->
            True

        Level2 ->
            countRolesCompleted player Level1 >= 1

        _ ->
            previous level
                |> Maybe.map (countRolesCompleted player)
                |> Maybe.map (\count -> count >= 2)
                |> Maybe.withDefault False


countRolesCompleted : Player -> Level -> Int
countRolesCompleted player level =
    completedRoleCards player
        |> List.map .level
        |> List.filter (\l -> l == level)
        |> List.length


accessibleRoles : Player -> { roles : List (RoleCard msg), nextLevelRule : Maybe String }
accessibleRoles player =
    let
        levels : { levels : List Level, nextLevelRule : Maybe String }
        levels =
            accessibleLevels player
    in
    { roles =
        RoleCard.all
            |> List.filter (\card -> List.member card.level levels.levels)
            |> List.filter (\card -> progressOf card.role player |> not << completed)
    , nextLevelRule = levels.nextLevelRule
    }
