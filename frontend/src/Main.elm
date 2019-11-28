module Main exposing (..)

import App
import App.Home
import App.Layout
import App.TreeStatus
import App.TreeStatus.Api
import App.TreeStatus.Types
import App.UserScopes
import Hawk
import Html exposing (..)
import Navigation
import String
import Task
import Time exposing (Time)
import Utils


main : Program App.Flags App.Model App.Msg
main =
    Navigation.programWithFlags App.UrlChange
        { init = init
        , view = App.Layout.view viewRoute
        , update = update
        , subscriptions = subscriptions
        }


init : App.Flags -> Navigation.Location -> ( App.Model, Cmd App.Msg )
init flags location =
    let
        route =
            App.parseLocation location

        model =
            { history = [ location ]
            , route = route
            , version = flags.version
            , channel = flags.channel
            , taskclusterRootUrl = flags.taskclusterRootUrl
            , taskclusterScopes = App.UserScopes.init flags.taskclusterRootUrl
            , taskclusterCredentials = flags.taskclusterCredentials
            , treestatus = App.TreeStatus.init flags.treestatusUrl
            }

        ( model_, appCmd ) =
            initRoute model route
    in
    ( model_
    , Cmd.batch
        [ appCmd
        , Task.perform App.CheckTaskclusterCredentials Time.now
        ]
    )


initRoute : App.Model -> App.Route -> ( App.Model, Cmd App.Msg )
initRoute model route =
    case route of
        App.NotFoundRoute ->
            model ! []

        App.HomeRoute ->
            { model
                | treestatus =
                    App.TreeStatus.init model.treestatus.baseUrl
            }
                ! [ Utils.performMsg (App.UserScopesMsg App.UserScopes.FetchScopes)
                  , App.navigateTo (App.TreeStatusRoute App.TreeStatus.Types.ShowTreesRoute)
                  ]

        App.TreeStatusRoute route ->
            model
                ! [ Utils.performMsg (App.TreeStatusMsg (App.TreeStatus.Types.NavigateTo route))
                  , Utils.performMsg (App.UserScopesMsg App.UserScopes.FetchScopes)
                  ]


update : App.Msg -> App.Model -> ( App.Model, Cmd App.Msg )
update msg model =
    case msg of
        --
        -- ROUTING
        --
        App.UrlChange location ->
            { model
                | history = location :: model.history
                , route = App.parseLocation location
            }
                ! []

        App.NavigateTo route ->
            let
                ( newModel, newCmd ) =
                    initRoute model route
            in
            ( newModel
            , Cmd.batch
                [ App.navigateTo route
                , newCmd
                ]
            )

        App.NavigateToUrl url ->
            ( model, Navigation.load url )

        --
        -- HAWK REQUESTS
        --
        App.HawkMsg hawkMsg ->
            let
                ( requestId, cmd, response ) =
                    Hawk.update hawkMsg

                routeHawkMsg route =
                    if String.startsWith "TreeStatus" route then
                        route
                            |> String.dropLeft (String.length "TreeStatus")
                            |> App.TreeStatus.Api.hawkResponse response
                            |> Cmd.map App.TreeStatusMsg
                    else if String.startsWith "UserScopes" route then
                        route
                            |> String.dropLeft (String.length "UserScopes")
                            |> App.UserScopes.hawkResponse response
                            |> Cmd.map App.UserScopesMsg
                    else
                        Cmd.none

                appCmd =
                    requestId
                        |> Maybe.map routeHawkMsg
                        |> Maybe.withDefault Cmd.none
            in
            ( model
            , Cmd.batch
                [ Cmd.map App.HawkMsg cmd
                , appCmd
                ]
            )

        App.UserScopesMsg msg_ ->
            let
                ( newModel, newCmd, hawkCmd ) =
                    App.UserScopes.update msg_ model.taskclusterScopes
            in
            ( { model | taskclusterScopes = newModel }
            , hawkCmd
                |> Maybe.map (\req -> [ hawkSend model.taskclusterCredentials "UserScopes" req ])
                |> Maybe.withDefault []
                |> List.append [ Cmd.map App.UserScopesMsg newCmd ]
                |> Cmd.batch
            )

        App.TreeStatusMsg msg_ ->
            let
                route =
                    case model.route of
                        App.TreeStatusRoute x ->
                            x

                        _ ->
                            App.TreeStatus.Types.ShowTreesRoute

                ( newModel, newCmd, hawkCmd ) =
                    App.TreeStatus.update route msg_ model.treestatus
            in
            ( { model | treestatus = newModel }
            , hawkCmd
                |> Maybe.map (\req -> [ hawkSend model.taskclusterCredentials "TreeStatus" req ])
                |> Maybe.withDefault []
                |> List.append [ Cmd.map App.TreeStatusMsg newCmd ]
                |> Cmd.batch
            )

        App.CheckTaskclusterCredentials time ->
            let
                expires =
                    model.taskclusterCredentials
                        |> Maybe.map .expires
                        |> Maybe.withDefault 0
            in
            if expires /= 0 && time > toFloat expires then
                -- XXX: create a port to only request new taskcluster credentials
                model ! [ Utils.performMsg (App.NavigateToUrl <| App.loginUrl model) ]
            else
                model ! []


hawkSend :
    Maybe Hawk.Credentials
    -> String
    -> Hawk.Request
    -> Cmd App.Msg
hawkSend credentials page request =
    let
        pagedRequest =
            { request | id = page ++ request.id }
    in
    case credentials of
        Just credentials ->
            Hawk.send pagedRequest credentials
                |> Cmd.map App.HawkMsg

        Nothing ->
            Cmd.none


viewRoute : App.Model -> Html App.Msg
viewRoute model =
    case model.route of
        App.NotFoundRoute ->
            App.Layout.viewNotFound model

        App.HomeRoute ->
            App.Home.view model

        App.TreeStatusRoute route ->
            App.TreeStatus.view
                route
                model.taskclusterCredentials
                model.taskclusterScopes
                model.treestatus
                |> Html.map App.TreeStatusMsg


subscriptions : App.Model -> Sub App.Msg
subscriptions model =
    Sub.batch
        [ Hawk.subscriptions App.HawkMsg
        , Time.every (50 * Time.second) App.CheckTaskclusterCredentials
        ]
