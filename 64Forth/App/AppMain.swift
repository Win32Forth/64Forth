//
//  AppMain.swift
//  64Forth
//
//  Public domain.
//
//  Process entry: agent/headless channel or normal SwiftUI GUI.
//

import Foundation

@main
enum AppMain {
    static func main() {
        if AgentChannel.isRequested {
            AgentChannel.runAndExit()
        }
        // Normal interactive product.
        SixtyFourForthApp.main()
    }
}
