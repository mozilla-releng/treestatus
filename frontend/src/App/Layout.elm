module App.Layout exposing (..)

import App
import App.TreeStatus.Types
import App.Utils
import Html exposing (..)
import Html.Attributes exposing (..)
import Utils


viewDropdown : String -> List (Html msg) -> List (Html msg)
viewDropdown title pages =
    [ div [ class "dropdown" ]
        [ a
            [ class "nav-link dropdown-toggle"
            , id ("dropdown" ++ title)
            , href "#"
            , attribute "data-toggle" "dropdown"
            , attribute "aria-haspopup" "true"
            , attribute "aria-expanded" "false"
            ]
            [ text title ]
        , div
            [ class "dropdown-menu dropdown-menu-right"
            , attribute "aria-labelledby" "dropdownServices"
            ]
            pages
        ]
    ]


viewUser : App.Model -> List (Html App.Msg)
viewUser model =
    case model.taskclusterCredentials of
        Just user ->
            let
                prefix =
                    "mozilla-auth0/ad|Mozilla-LDAP|"

                username =
                    user.clientId
                        |> String.dropLeft (String.length prefix)
                        |> String.split "/"
                        |> List.head
                        |> Maybe.withDefault user.clientId

                email =
                    if String.startsWith prefix user.clientId then
                        username ++ "@mozilla.com"
                    else
                        user.clientId
            in
            viewDropdown email
                [ a
                    [ class "dropdown-item"
                    , href <| model.taskclusterRootUrl ++ "/profile"
                    , target "_blank"
                    ]
                    [ text "Manage profile" ]
                , a
                    [ Utils.onClick <| App.NavigateToUrl <| App.logoutUrl model
                    , href "#"
                    , class "dropdown-item"
                    ]
                    [ text "Logout" ]
                ]

        Nothing ->
            [ a
                [ href <| App.loginUrl model
                , class "nav-link"
                ]
                [ text "Login" ]
            ]


viewNavBar : App.Model -> List (Html App.Msg)
viewNavBar model =
    [ a
        [ Utils.onClick (App.NavigateTo (App.TreeStatusRoute App.TreeStatus.Types.ShowTreesRoute))
        , href "#"
        , class "navbar-brand"
        ]
        [ text "Release Engineering" ]
    , ul [ class "navbar-nav" ]
        [ li [ class "nav-item" ] (viewUser model)
        ]
    ]


viewFooter : App.Model -> List (Html App.Msg)
viewFooter model =
    [ hr [] []
    , ul []
        [ li []
            [ a [ href "https://github.com/mozilla/release-services/blob/master/CONTRIBUTING.rst" ]
                [ text "Contribute" ]
            ]
        , li []
            [ a [ href "https://github.com/mozilla/release-services/issues/new" ]
                [ text "Contact" ]
            ]
        ]
    , div []
        [ text "version: "
        , a [ href ("https://github.com/mozilla/release-services/releases/tag/v" ++ model.version) ]
            [ text model.version ]
        ]
    ]


viewNotFound : App.Model -> Html.Html App.Msg
viewNotFound model =
    div [ class "hero-unit" ]
        [ h1 [] [ text "Page Not Found" ] ]


view : (App.Model -> Html.Html App.Msg) -> App.Model -> Html.Html App.Msg
view viewRoute model =
    let
        routeName =
            case model.route of
                App.HomeRoute ->
                    "home"

                App.TreeStatusRoute _ ->
                    "treestatus"

                _ ->
                    ""

        isLoading =
            case model.taskclusterCredentials of
                Just _ ->
                    if List.length model.taskclusterScopes.scopes == 0 then
                        True
                    else
                        False

                _ ->
                    True
    in
    div [ id ("page-" ++ routeName) ]
        [ nav
            [ id "navbar"
            , class "navbar navbar-toggleable-md bg-faded navbar-inverse"
            ]
            [ div [ class "container" ] (viewNavBar model) ]
        , div [ id "content" ]
            [ div [ class "container" ]
                [ if isLoading then
                    App.Utils.loading
                  else
                    viewRoute model
                ]
            ]
        , footer [ class "container" ] (viewFooter model)
        ]
