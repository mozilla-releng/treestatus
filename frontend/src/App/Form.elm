module App.Form exposing (..)

import Form
import Form.Input
import Html exposing (..)
import Html.Attributes exposing (..)


maybeAppend : Maybe a -> (a -> b) -> List b -> List b
maybeAppend maybeValue f =
    maybeValue
        |> Maybe.map (\x -> [ f x ])
        |> Maybe.withDefault []
        |> List.append


maybeAppendError : Maybe a -> List (Html b) -> List (Html b)
maybeAppendError maybeError =
    maybeAppend maybeError
        (\x ->
            div [ class "form-control-feedback" ]
                [ text (toString x) ]
        )


maybeAppendHelp : Maybe String -> List (Html a) -> List (Html a)
maybeAppendHelp maybeHelp =
    maybeAppend maybeHelp
        (\x ->
            small [ class "form-text text-muted" ]
                [ text x ]
        )


maybeAppendLabel : Maybe String -> List (Html a) -> List (Html a)
maybeAppendLabel maybeLabel =
    maybeAppend maybeLabel
        (\x ->
            label [ class "control-label" ]
                [ text x ]
        )


errorClass : Maybe error -> String
errorClass maybeError =
    maybeError
        |> Maybe.map (\_ -> "has-danger")
        |> Maybe.withDefault ""


viewField :
    Maybe a
    -> Maybe String
    -> List (Html Form.Msg)
    -> Html Form.Msg
    -> Html Form.Msg
viewField maybeError maybeLabel helpNodes inputNode =
    div
        [ class ("form-group " ++ errorClass maybeError) ]
        ([]
            |> List.append helpNodes
            |> maybeAppendError maybeError
            |> List.append [ inputNode ]
            |> maybeAppendLabel maybeLabel
        )


viewTextInput :
    Form.FieldState () String
    -> String
    -> List (Html Form.Msg)
    -> List (Attribute Form.Msg)
    -> Html Form.Msg
viewTextInput state labelText helpNodes attributes =
    viewField
        (if state.liveError == Nothing then
            state.error
         else
            state.liveError
        )
        (Just labelText)
        helpNodes
        (Form.Input.textInput state
            (attributes
                |> List.append
                    [ class "form-control"
                    , value (Maybe.withDefault "" state.value)
                    ]
            )
        )


viewSelectInput :
    Form.FieldState a String
    -> String
    -> List (Html Form.Msg)
    -> List ( String, String )
    -> List (Attribute Form.Msg)
    -> Html Form.Msg
viewSelectInput state labelText helpNodes options attributes =
    viewField
        (if state.liveError == Nothing then
            state.error
         else
            state.liveError
        )
        (Just labelText)
        helpNodes
        (Form.Input.selectInput
            options
            state
            (attributes |> List.append [ class "form-control" ])
        )


viewRadioInput :
    Form.FieldState a String
    -> String
    -> List (Html Form.Msg)
    -> List ( String, String )
    -> List (Attribute Form.Msg)
    -> Html Form.Msg
viewRadioInput state labelText helpNodes options attributes =
    let
        item ( v, l ) =
            label
                [ class "radio-inline" ]
                [ Form.Input.radioInput v state []
                , text l
                ]
    in
    viewField
        (if state.liveError == Nothing then
            state.error
         else
            state.liveError
        )
        (Just labelText)
        helpNodes
        (div [] (List.map item options))


viewCheckboxInput :
    Form.FieldState a Bool
    -> String
    -> Html Form.Msg
viewCheckboxInput state labelText =
    label
        [ class "custom-control custom-checkbox" ]
        [ Form.Input.checkboxInput state [ class "custom-control-input" ]
        , span
            [ class "custom-control-indicator" ]
            []
        , span
            [ class "custom-control-description" ]
            [ text labelText ]
        ]


viewButton : String -> List (Attribute msg) -> Html msg
viewButton labelText attributes =
    button
        (attributes
            |> List.append
                [ type_ "submit"
                , class "btn btn-outline-primary"
                ]
        )
        [ text labelText ]
