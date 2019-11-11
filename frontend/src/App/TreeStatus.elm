module App.TreeStatus exposing (..)

import App.TreeStatus.Api
import App.TreeStatus.Form
import App.TreeStatus.Types
import App.TreeStatus.View
import App.Types
import App.UserScopes
import App.Utils
import Form
import Hawk
import Html exposing (..)
import Html.Attributes exposing (..)
import Http
import Navigation
import RemoteData
import Title
import UrlParser exposing ((</>))
import Utils


--
-- ROUTING
--


routeParser : UrlParser.Parser (App.TreeStatus.Types.Route -> a) a
routeParser =
    UrlParser.oneOf
        [ UrlParser.map App.TreeStatus.Types.ShowTreesRoute UrlParser.top
        , UrlParser.map App.TreeStatus.Types.AddTreeRoute (UrlParser.s "add")
        , UrlParser.map App.TreeStatus.Types.UpdateTreesRoute (UrlParser.s "update")
        , UrlParser.map App.TreeStatus.Types.DeleteTreesRoute (UrlParser.s "delete")
        , UrlParser.map App.TreeStatus.Types.ShowTreeRoute (UrlParser.s "show" </> UrlParser.string)
        ]


reverseRoute : App.TreeStatus.Types.Route -> String
reverseRoute route =
    let
        path =
            case route of
                App.TreeStatus.Types.ShowTreesRoute ->
                    "/"

                App.TreeStatus.Types.AddTreeRoute ->
                    "/add"

                App.TreeStatus.Types.UpdateTreesRoute ->
                    "/update"

                App.TreeStatus.Types.DeleteTreesRoute ->
                    "/delete"

                App.TreeStatus.Types.ShowTreeRoute name ->
                    "/show/" ++ name
    in
    "/treestatus" ++ path


page : (App.TreeStatus.Types.Route -> a) -> App.Types.Page a b
page outRoute =
    { title = "TreeStatus"
    , description = "Current status of Mozilla's version-control repositories."
    , matcher = UrlParser.map outRoute (UrlParser.s "treestatus" </> routeParser)
    }



--
-- UPDATE
--


init : String -> App.TreeStatus.Types.Model App.TreeStatus.Form.AddTree App.TreeStatus.Form.UpdateTree App.TreeStatus.Form.UpdateStack App.TreeStatus.Form.UpdateLog
init url =
    { baseUrl = url
    , treesAlerts = []
    , trees = RemoteData.NotAsked
    , treesSelected = []
    , tree = RemoteData.NotAsked
    , treeLogs = RemoteData.NotAsked
    , treeLogsAll = RemoteData.NotAsked
    , showMoreTreeLogs = False
    , formAddTree = App.TreeStatus.Form.initAddTree
    , formUpdateTree = App.TreeStatus.Form.initUpdateTree ""
    , showUpdateStackForm = Nothing
    , formUpdateStack = App.TreeStatus.Form.initUpdateStack ""
    , recentChangesAlerts = []
    , recentChanges = RemoteData.NotAsked
    , deleteTreesConfirm = False
    , deleteError = Nothing
    , showUpdateLog = Nothing
    , formUpdateLog = App.TreeStatus.Form.initUpdateLog ""
    }


update :
    App.TreeStatus.Types.Route
    -> App.TreeStatus.Types.Msg
    -> App.TreeStatus.Types.Model App.TreeStatus.Form.AddTree App.TreeStatus.Form.UpdateTree App.TreeStatus.Form.UpdateStack App.TreeStatus.Form.UpdateLog
    -> ( App.TreeStatus.Types.Model App.TreeStatus.Form.AddTree App.TreeStatus.Form.UpdateTree App.TreeStatus.Form.UpdateStack App.TreeStatus.Form.UpdateLog, Cmd App.TreeStatus.Types.Msg, Maybe Hawk.Request )
update currentRoute msg model =
    case msg of
        App.TreeStatus.Types.NavigateTo route ->
            let
                fetchIfNotAsked data fetch =
                    if data == RemoteData.NotAsked then
                        fetch
                    else
                        Cmd.none

                fetchRecentChangesIfNotAsked =
                    fetchIfNotAsked
                        model.recentChanges
                        (App.TreeStatus.Api.fetchRecentChanges model.baseUrl)

                showAllTrees =
                    ( { model | trees = RemoteData.Loading }
                    , Cmd.batch
                        [ Title.set_title "TreeStatus"
                        , App.TreeStatus.Api.fetchTrees model.baseUrl
                        , App.TreeStatus.Api.fetchRecentChanges model.baseUrl
                        ]
                    )

                redirectToTrees =
                    List.isEmpty model.treesSelected
                        && (currentRoute
                                == App.TreeStatus.Types.UpdateTreesRoute
                                || currentRoute
                                == App.TreeStatus.Types.DeleteTreesRoute
                           )

                ( newModel, newCmd ) =
                    -- in case there are no trees selected and we end up on update
                    -- url we should redirect to ShowTreesRoute
                    if redirectToTrees then
                        showAllTrees
                    else
                        case route of
                            App.TreeStatus.Types.ShowTreesRoute ->
                                showAllTrees

                            App.TreeStatus.Types.AddTreeRoute ->
                                ( { model | treesAlerts = [] }
                                , fetchIfNotAsked
                                    model.recentChanges
                                    (App.TreeStatus.Api.fetchRecentChanges model.baseUrl)
                                )

                            App.TreeStatus.Types.UpdateTreesRoute ->
                                ( { model | treesAlerts = [] }
                                , fetchRecentChangesIfNotAsked
                                )

                            App.TreeStatus.Types.DeleteTreesRoute ->
                                ( { model
                                    | treesAlerts = []
                                    , deleteTreesConfirm = False
                                    , deleteError = Nothing
                                  }
                                , fetchRecentChangesIfNotAsked
                                )

                            App.TreeStatus.Types.ShowTreeRoute name ->
                                ( { model
                                    | tree = RemoteData.Loading
                                    , treeLogs = RemoteData.Loading
                                    , treeLogsAll = RemoteData.NotAsked
                                    , treesSelected = [ name ]
                                  }
                                , Cmd.batch
                                    [ App.TreeStatus.Api.fetchTree model.baseUrl name
                                    , App.TreeStatus.Api.fetchTreeLogs model.baseUrl name False
                                    , fetchRecentChangesIfNotAsked
                                    ]
                                )

                newRoute =
                    if redirectToTrees then
                        App.TreeStatus.Types.ShowTreesRoute
                    else
                        route
            in
            ( newModel
            , Cmd.batch
                [ "/static/ui"
                    ++ reverseRoute newRoute
                    |> Navigation.newUrl
                , newCmd
                ]
            , Nothing
            )

        App.TreeStatus.Types.GetTreesResult trees ->
            ( { model | trees = trees }, Cmd.none, Nothing )

        App.TreeStatus.Types.GetTreeResult tree ->
            ( { model | tree = tree }, Cmd.none, Nothing )

        App.TreeStatus.Types.GetTreeLogsResult logs ->
            ( { model | treeLogs = logs }, Cmd.none, Nothing )

        App.TreeStatus.Types.GetTreeLogsAllResult logs ->
            ( { model | treeLogsAll = logs }, Cmd.none, Nothing )

        App.TreeStatus.Types.GetRecentChangesResult recentChanges ->
            ( { model | recentChanges = recentChanges }, Cmd.none, Nothing )

        App.TreeStatus.Types.GetTreeLogs name all ->
            ( model
            , App.TreeStatus.Api.fetchTreeLogs model.baseUrl name True
            , Nothing
            )

        App.TreeStatus.Types.FormAddTreeMsg formMsg ->
            let
                ( newModel, hawkRequest ) =
                    App.TreeStatus.Form.updateAddTree model formMsg
            in
            ( newModel
            , Cmd.none
            , hawkRequest
            )

        App.TreeStatus.Types.FormAddTreeResult result ->
            ( { model | treesAlerts = App.Utils.getAlerts result }
            , Cmd.batch
                [ Utils.performMsg App.TreeStatus.Form.resetAddTree
                    |> Cmd.map App.TreeStatus.Types.FormAddTreeMsg
                , "/static/ui"
                    ++ reverseRoute App.TreeStatus.Types.ShowTreesRoute
                    |> Navigation.newUrl
                ]
            , Nothing
            )

        App.TreeStatus.Types.FormUpdateTreesMsg formMsg ->
            let
                ( newModel, hawkRequest ) =
                    App.TreeStatus.Form.updateUpdateTree currentRoute model formMsg
            in
            ( newModel
            , Cmd.none
            , hawkRequest
            )

        App.TreeStatus.Types.FormUpdateTreesResult result ->
            ( { model | treesAlerts = App.Utils.getAlerts result }
            , Cmd.batch
                [ App.TreeStatus.Api.fetchTrees model.baseUrl
                , App.TreeStatus.Api.fetchRecentChanges model.baseUrl
                , Utils.performMsg App.TreeStatus.Form.resetUpdateTree
                    |> Cmd.map App.TreeStatus.Types.FormUpdateTreesMsg
                , "/static/ui"
                    ++ reverseRoute App.TreeStatus.Types.ShowTreesRoute
                    |> Navigation.newUrl
                ]
            , Nothing
            )

        App.TreeStatus.Types.SelectAllTrees ->
            let
                treesSelected =
                    case model.trees of
                        RemoteData.Success trees ->
                            List.map .name trees

                        _ ->
                            []
            in
            ( { model | treesSelected = treesSelected }
            , Cmd.none
            , Nothing
            )

        App.TreeStatus.Types.SelectTree name ->
            let
                treesSelected =
                    if List.member name model.treesSelected then
                        model.treesSelected
                    else
                        name :: model.treesSelected
            in
            ( { model | treesSelected = treesSelected }
            , Cmd.none
            , Nothing
            )

        App.TreeStatus.Types.UnselectAllTrees ->
            ( { model | treesSelected = [] }
            , Cmd.none
            , Nothing
            )

        App.TreeStatus.Types.UnselectTree name ->
            let
                treesSelected =
                    List.filter (\x -> x /= name) model.treesSelected
            in
            ( { model | treesSelected = treesSelected }
            , Cmd.none
            , Nothing
            )

        App.TreeStatus.Types.DeleteTrees ->
            let
                filterOutTrees =
                    List.filter
                        (\x -> Basics.not (List.member x.name model.treesSelected))

                filterTrees =
                    List.filter
                        (\x -> List.member x.name model.treesSelected)

                treesToDelete =
                    model.trees
                        |> RemoteData.map filterTrees
                        |> RemoteData.withDefault []

                request =
                    Hawk.Request
                        "DeleteTrees"
                        "DELETE"
                        (model.baseUrl ++ "/trees2")
                        [ Http.header "Accept" "application/json" ]
                        (Http.jsonBody (App.TreeStatus.Api.encoderTreeNames treesToDelete))
            in
            if model.deleteTreesConfirm then
                ( { model
                    | treesSelected = []
                    , trees = RemoteData.map filterOutTrees model.trees
                  }
                , Cmd.none
                , Just request
                )
            else
                ( { model | deleteError = Just "You need to confirm to be able to delete tree(s)." }
                , Cmd.none
                , Nothing
                )

        App.TreeStatus.Types.DeleteTreesResult result ->
            ( { model | treesAlerts = App.Utils.getAlerts result }
            , "/static/ui"
                ++ reverseRoute App.TreeStatus.Types.ShowTreesRoute
                |> Navigation.newUrl
            , Nothing
            )

        App.TreeStatus.Types.RevertChange stack ->
            ( { model | recentChangesAlerts = [] }
            , Cmd.none
            , Just
                (Hawk.Request
                    "RevertChange"
                    "DELETE"
                    (model.baseUrl ++ "/stack2/restore/" ++ toString stack)
                    [ Http.header "Accept" "application/json" ]
                    Http.emptyBody
                )
            )

        App.TreeStatus.Types.DiscardChange stack ->
            ( { model | recentChangesAlerts = [] }
            , Cmd.none
            , Just
                (Hawk.Request
                    "DiscardChange"
                    "DELETE"
                    (model.baseUrl ++ "/stack2/discard/" ++ toString stack)
                    [ Http.header "Accept" "application/json" ]
                    Http.emptyBody
                )
            )

        App.TreeStatus.Types.RecentChangeResult result ->
            ( { model | recentChangesAlerts = App.Utils.getAlerts result }
            , Cmd.batch
                [ App.TreeStatus.Api.fetchRecentChanges model.baseUrl
                , App.TreeStatus.Api.fetchTrees model.baseUrl
                ]
            , Nothing
            )

        App.TreeStatus.Types.DeleteTreesConfirmToggle ->
            ( { model | deleteTreesConfirm = Basics.not model.deleteTreesConfirm }
            , Cmd.none
            , Nothing
            )

        App.TreeStatus.Types.UpdateStackShow stack ->
            let
                ( reason, category, status ) =
                    case model.recentChanges of
                        RemoteData.Success recentChanges ->
                            recentChanges
                                |> List.filter (\x -> x.id == stack)
                                |> List.head
                                |> Maybe.map
                                    (\x ->
                                        x.trees
                                            |> List.head
                                            |> Maybe.map
                                                (\y ->
                                                    ( y.last_state.current_reason
                                                    , y.last_state.current_tags |> List.head |> Maybe.withDefault ""
                                                    , y.last_state.current_status
                                                    )
                                                )
                                            |> Maybe.withDefault ( "", "", "" )
                                    )
                                |> Maybe.withDefault ( "", "", "" )

                        _ ->
                            ( "", "", "" )
            in
            ( { model
                | showUpdateStackForm = Just stack
                , formUpdateStack = Form.initial (App.TreeStatus.Form.initUpdateStackFields reason category) (App.TreeStatus.Form.validateUpdateLog status)
              }
            , Cmd.none
            , Nothing
            )

        App.TreeStatus.Types.FormUpdateStackMsg formMsg ->
            let
                ( newModel, hawkRequest ) =
                    App.TreeStatus.Form.updateUpdateStack model formMsg
            in
            ( newModel
            , Cmd.none
            , hawkRequest
            )

        App.TreeStatus.Types.FormUpdateStackResult result ->
            case currentRoute of
                App.TreeStatus.Types.ShowTreeRoute name ->
                    ( { model
                        | recentChangesAlerts = App.Utils.getAlerts result
                        , showUpdateStackForm = Nothing
                        , treeLogs = RemoteData.Loading
                        , treeLogsAll = RemoteData.Loading
                      }
                    , Cmd.batch
                        [ App.TreeStatus.Api.fetchRecentChanges model.baseUrl
                        , App.TreeStatus.Api.fetchTrees model.baseUrl
                        , App.TreeStatus.Api.fetchTreeLogs model.baseUrl name False
                        , App.TreeStatus.Api.fetchTreeLogs model.baseUrl name True
                        ]
                    , Nothing
                    )

                _ ->
                    ( { model
                        | recentChangesAlerts = App.Utils.getAlerts result
                        , showUpdateStackForm = Nothing
                      }
                    , Cmd.batch
                        [ App.TreeStatus.Api.fetchRecentChanges model.baseUrl
                        , App.TreeStatus.Api.fetchTrees model.baseUrl
                        ]
                    , Nothing
                    )

        App.TreeStatus.Types.UpdateLogShow logId ->
            let
                treeLogs =
                    if RemoteData.isSuccess model.treeLogsAll then
                        model.treeLogsAll
                    else
                        model.treeLogs

                ( reason, category, status ) =
                    case treeLogs of
                        RemoteData.Success logs ->
                            logs
                                |> List.filter (\x -> x.id == logId)
                                |> List.head
                                |> Maybe.map
                                    (\x ->
                                        ( x.reason
                                        , x.tags
                                            |> List.head
                                            |> Maybe.withDefault ""
                                        , x.status
                                        )
                                    )
                                |> Maybe.withDefault ( "", "", "" )

                        _ ->
                            ( "", "", "" )
            in
            ( { model
                | showUpdateLog = Just logId
                , formUpdateLog = Form.initial (App.TreeStatus.Form.initUpdateLogFields reason category) (App.TreeStatus.Form.validateUpdateLog status)
              }
            , Cmd.none
            , Nothing
            )

        App.TreeStatus.Types.FormUpdateLogMsg formMsg ->
            let
                ( newModel, hawkRequest ) =
                    App.TreeStatus.Form.updateUpdateLog model formMsg
            in
            ( newModel
            , Cmd.none
            , hawkRequest
            )

        App.TreeStatus.Types.FormUpdateLogResult result ->
            case currentRoute of
                App.TreeStatus.Types.ShowTreeRoute name ->
                    ( { model
                        | treeLogs = RemoteData.Loading
                        , treeLogsAll = RemoteData.Loading
                      }
                    , Cmd.batch
                        [ App.TreeStatus.Api.fetchTreeLogs model.baseUrl name False
                        , App.TreeStatus.Api.fetchTreeLogs model.baseUrl name True
                        ]
                    , Nothing
                    )

                _ ->
                    ( model
                    , Cmd.none
                    , Nothing
                    )


view :
    App.TreeStatus.Types.Route
    -> Maybe Hawk.Credentials
    -> App.UserScopes.Model
    -> App.TreeStatus.Types.Model App.TreeStatus.Form.AddTree App.TreeStatus.Form.UpdateTree App.TreeStatus.Form.UpdateStack App.TreeStatus.Form.UpdateLog
    -> Html App.TreeStatus.Types.Msg
view route credentials scopes model =
    let
        isLoadingRemoteData remotedata =
            RemoteData.isLoading remotedata || RemoteData.isNotAsked remotedata

        isLoadingScopes =
            case credentials of
                Just _ ->
                    if List.length scopes.scopes == 0 then
                        True
                    else
                        False

                _ ->
                    True

        isLoading =
            case route of
                App.TreeStatus.Types.ShowTreesRoute ->
                    isLoadingRemoteData model.trees

                App.TreeStatus.Types.AddTreeRoute ->
                    False

                App.TreeStatus.Types.UpdateTreesRoute ->
                    isLoadingRemoteData model.trees

                App.TreeStatus.Types.DeleteTreesRoute ->
                    False

                App.TreeStatus.Types.ShowTreeRoute name ->
                    isLoadingRemoteData model.tree
                        || isLoadingRemoteData model.treeLogs
                        || RemoteData.isLoading model.treeLogsAll
    in
    div [ class "container" ]
        [ h1 [] [ text "TreeStatus" ]
        , p [ class "lead" ]
            [ text "Current status of Mozilla's version-control repositories." ]
        , if isLoading then
            App.Utils.loading
          else
            viewLoaded route scopes.scopes model
        ]


viewLoaded :
    App.TreeStatus.Types.Route
    -> List String
    -> App.TreeStatus.Types.Model App.TreeStatus.Form.AddTree App.TreeStatus.Form.UpdateTree App.TreeStatus.Form.UpdateStack App.TreeStatus.Form.UpdateLog
    -> Html App.TreeStatus.Types.Msg
viewLoaded route scopes model =
    div []
        ([]
            |> App.Utils.appendItem
                (App.Utils.viewAlerts model.recentChangesAlerts)
            |> App.Utils.appendItems
                (App.TreeStatus.View.viewRecentChanges scopes model.showUpdateStackForm model.formUpdateStack model.recentChanges)
            |> App.Utils.appendItem
                (App.Utils.viewAlerts model.treesAlerts)
            |> App.Utils.appendItem
                (App.TreeStatus.View.viewTreesTitle route)
            |> App.Utils.appendItem
                (App.TreeStatus.View.viewButtons route scopes model)
            |> App.Utils.appendItems
                (case route of
                    App.TreeStatus.Types.ShowTreesRoute ->
                        App.TreeStatus.View.viewTrees scopes model.trees model.treesSelected

                    App.TreeStatus.Types.AddTreeRoute ->
                        [ App.TreeStatus.Form.viewAddTree model.formAddTree
                            |> Html.map App.TreeStatus.Types.FormAddTreeMsg
                        ]

                    App.TreeStatus.Types.UpdateTreesRoute ->
                        [ App.TreeStatus.Form.viewUpdateTree model.treesSelected model.trees model.formUpdateTree
                            |> Html.map App.TreeStatus.Types.FormUpdateTreesMsg
                        ]

                    App.TreeStatus.Types.DeleteTreesRoute ->
                        App.TreeStatus.View.viewConfirmDelete model.deleteError model.deleteTreesConfirm model.treesSelected

                    App.TreeStatus.Types.ShowTreeRoute name ->
                        App.TreeStatus.View.viewTree scopes model.tree model.treeLogs model.treeLogsAll model.showUpdateLog model.formUpdateLog name
                )
        )
