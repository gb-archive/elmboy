module Main exposing (main)

import Array exposing (Array)
import Bootstrap.Modal as Modal
import Browser
import Browser.Events
import Bytes
import Bytes.Decode
import Component.Cartridge as Cartridge
import Component.Joypad exposing (GameBoyButton(..))
import Component.PPU as PPU
import Component.PPU.GameBoyScreen as GameBoyScreen
import Emulator
import File
import File.Select
import GameBoy exposing (GameBoy)
import Html exposing (Html)
import Json.Decode as Decode
import Model exposing (EmulationMode(..), Model)
import Msg exposing (Msg(..))
import Ports
import Task
import UI.KeyDecoder
import Util
import View


init : () -> ( Model, Cmd Msg )
init _ =
    ( { gameBoy = Nothing, emulationMode = Manual, frameTimes = [], errorModal = Nothing }, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        AnimationFrameDelta time ->
            case model.gameBoy of
                Just gameBoy ->
                    let
                        emulatedGameBoy =
                            Emulator.emulateCycles (cyclesPerSecond // 60) gameBoy
                    in
                    ( { model | gameBoy = Just emulatedGameBoy, frameTimes = time :: List.take 120 model.frameTimes }
                    , Ports.setPixelsFromBatches { canvasId = canvasId, pixelBatches = GameBoyScreen.serializePixelBatches (PPU.getLastCompleteFrame emulatedGameBoy.ppu) }
                    )

                Nothing ->
                    ( model, Cmd.none )

        ButtonDown button ->
            ( { model | gameBoy = model.gameBoy |> Maybe.map (GameBoy.setButtonStatus button True) }
            , Cmd.none
            )

        ButtonUp button ->
            ( { model | gameBoy = model.gameBoy |> Maybe.map (GameBoy.setButtonStatus button False) }
            , Cmd.none
            )

        Reset ->
            init ()

        Pause ->
            ( { model | emulationMode = Manual }, Cmd.none )

        Resume ->
            ( { model | emulationMode = OnAnimationFrame }, Cmd.none )

        OpenFileSelect ->
            ( model, File.Select.file [] FileSelected )

        FileSelected file ->
            file
                |> File.toBytes
                |> Task.map (\bytes -> Bytes.Decode.decode (Util.uint8ArrayDecoder (Bytes.width bytes)) bytes |> Maybe.andThen Cartridge.fromBytes)
                |> Task.perform CartridgeSelected
                |> Tuple.pair model

        CartridgeSelected maybeCartridge ->
            case maybeCartridge of
                Just cartridge ->
                    ( { model | gameBoy = Just (GameBoy.init cartridge), emulationMode = OnAnimationFrame }, Cmd.none )

                Nothing ->
                    let
                        errorModal =
                            { visibility = Modal.shown
                            , title = "Unsupported ROM"
                            , body = "Your selected ROM is not yet supported by Elmboy. This is usually the case due to an unsupported memory bank controller required by the ROM you're trying to run. Please select another game and report the issue in the GitHub issue tracker."
                            }
                    in
                    ( { model | errorModal = Just errorModal }, Cmd.none )

        CloseErrorModal ->
            ( { model | errorModal = Nothing }, Cmd.none )


main : Program () Model Msg
main =
    Browser.element
        { view = View.view canvasId fileInputId
        , init = init
        , update = update
        , subscriptions = subscriptions
        }


subscriptions : Model -> Sub Msg
subscriptions model =
    let
        animationFrameSubscription =
            case model.emulationMode of
                OnAnimationFrame ->
                    Browser.Events.onAnimationFrameDelta AnimationFrameDelta

                _ ->
                    Sub.none
    in
    Sub.batch
        [ animationFrameSubscription
        , Browser.Events.onKeyDown (Decode.map ButtonDown UI.KeyDecoder.decodeKey)
        , Browser.Events.onKeyUp (Decode.map ButtonUp UI.KeyDecoder.decodeKey)
        ]


cyclesPerSecond : Int
cyclesPerSecond =
    4 * 1024 * 1024


canvasId : String
canvasId =
    "screen"


fileInputId : String
fileInputId =
    "romFileInput"
