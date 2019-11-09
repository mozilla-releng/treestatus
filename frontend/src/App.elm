module App exposing (..)

import App.TreeStatus
import App.TreeStatus.Form
import App.TreeStatus.Types
import App.Types
import App.UserScopes
import Hawk
import Navigation
import Time exposing (Time)
import UrlParser exposing ((</>), (<?>))


--
-- ROUTING
--
-- inspired by https://github.com/rofrol/elm-navigation-example
--


type Route
    = NotFoundRoute
    | HomeRoute
    | TreeStatusRoute App.TreeStatus.Types.Route


pages : List (App.Types.Page Route b)
pages =
    [ App.TreeStatus.page TreeStatusRoute
    ]


routeParser : UrlParser.Parser (Route -> a) a
routeParser =
    let
        parser =
            pages
                |> List.map (\x -> x.matcher)
                |> List.append
                    [ UrlParser.map HomeRoute UrlParser.top
                    , UrlParser.map NotFoundRoute (UrlParser.s "404")
                    ]
                |> UrlParser.oneOf
    in
    UrlParser.s "static" </> (UrlParser.s "ui" </> parser)


reverseRoute : Route -> String
reverseRoute route =
    let
        path =
            case route of
                NotFoundRoute ->
                    "/404"

                HomeRoute ->
                    "/"

                TreeStatusRoute route ->
                    App.TreeStatus.reverseRoute route
    in
    "/static/ui" ++ path


parseLocation : Navigation.Location -> Route
parseLocation location =
    location
        |> UrlParser.parsePath routeParser
        |> Maybe.withDefault NotFoundRoute


navigateTo : Route -> Cmd Msg
navigateTo route =
    route
        |> reverseRoute
        |> Navigation.newUrl


loginUrl : Model -> String
loginUrl model =
    let
        loginParams =
            [ ( "action", "login" )
            , ( "client_id", "releng-treestatus-" ++ model.channel )
            , ( "return_url"
              , model.history
                    |> List.head
                    |> Maybe.map .href
                    |> Maybe.withDefault ""
              )
            , ( "taskcluster_url", model.taskclusterRootUrl )
            , ( "scope", "project:releng:services/treestatus/*" )
            ]
    in
    "/static/login.html?"
        ++ (loginParams
                |> List.map (\( name, value ) -> name ++ "=" ++ value)
                |> String.join "&"
           )


logoutUrl : Model -> String
logoutUrl model =
    let
        loginParams =
            [ ( "action", "logout" )
            , ( "return_url"
              , model.history
                    |> List.head
                    |> Maybe.map .href
                    |> Maybe.withDefault ""
              )
            ]
    in
    "/static/login.html?"
        ++ (loginParams
                |> List.map (\( name, value ) -> name ++ "=" ++ value)
                |> String.join "&"
           )



--
-- TASKCLUSTER AUTH
--
--
-- FLAGS
--


type alias Flags =
    { taskclusterCredentials : Maybe Hawk.Credentials
    , taskclusterRootUrl : String
    , treestatusUrl : String
    , version : String
    , channel : String
    }



--
-- MODEL
--


type alias Model =
    { history : List Navigation.Location
    , route : Route
    , taskclusterRootUrl : String
    , taskclusterCredentials : Maybe Hawk.Credentials
    , taskclusterScopes : App.UserScopes.Model
    , treestatus : App.TreeStatus.Types.Model App.TreeStatus.Form.AddTree App.TreeStatus.Form.UpdateTree App.TreeStatus.Form.UpdateStack App.TreeStatus.Form.UpdateLog
    , version : String
    , channel : String
    }



--
-- MESSAGES
--


type Msg
    = UrlChange Navigation.Location
    | NavigateTo Route
    | NavigateToUrl String
    | HawkMsg Hawk.Msg
    | UserScopesMsg App.UserScopes.Msg
    | TreeStatusMsg App.TreeStatus.Types.Msg
    | CheckTaskclusterCredentials Time
