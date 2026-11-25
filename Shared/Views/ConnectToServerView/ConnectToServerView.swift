//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import SwiftUI

struct ConnectToServerView: View {

    #if os(tvOS)
    private enum Mode: CaseIterable, Displayable {
        case automatic
        case manual

        var displayTitle: String {
            switch self {
            case .automatic:
                L10n.automatic
            case .manual:
                L10n.manual
            }
        }
    }
    #endif

    @Default(.accentColor)
    private var accentColor

    @FocusState
    private var isURLFocused: Bool
    @FocusState
    private var focusedServerID: String?

    @Router
    private var router

    @State
    private var duplicateServer: ServerState? = nil

    @State
    private var url: String = ""

    #if os(tvOS)
    @State
    private var mode: Mode = .automatic
    @State
    private var hasFocusedFirstServer = false
    #endif

    @StateObject
    private var viewModel = ConnectToServerViewModel()

    private let timer = Timer.publish(every: 12, on: .main, in: .common).autoconnect()

    private func onEvent(_ event: ConnectToServerViewModel._Event) {
        switch event {
        case let .connected(server):
            UIDevice.feedback(.success)
            Notifications[.didConnectToServer].post(server)
            router.dismiss()

        case let .duplicateServer(server):
            UIDevice.feedback(.warning)
            duplicateServer = server

        case .error:
            UIDevice.feedback(.error)
            isURLFocused = true
        }
    }

    @ViewBuilder
    private var connectSection: some View {
        Section(L10n.connectToServer) {
            TextField(L10n.url, text: $url)
                .disableAutocorrection(true)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .focused($isURLFocused)
        }

        if viewModel.state == .connecting {
            Button(role: .cancel) {
                viewModel.cancel()
            } label: {
                Text(L10n.cancel)
                    .frame(maxWidth: .infinity)
            }
            .listRowInsets(.zero)
            .listRowBackground(Color.clear)
            #if os(iOS)
            .listRowSeparator(.hidden)
            #endif
            .fontWeight(.semibold)
            .backport
            .buttonStyle(.glassProminent.shadow(false))
            #if os(iOS)
            .controlSize(.large)
            #endif
            .frame(maxHeight: 75)
        } else {
            Button {
                isURLFocused = false
                viewModel.connect(url: url)
            } label: {
                Text(L10n.connect)
                    .frame(maxWidth: .infinity)
            }
            .listRowInsets(.zero)
            .listRowBackground(Color.clear)
            #if os(iOS)
            .listRowSeparator(.hidden)
            #endif
            .fontWeight(.semibold)
            .backport
            .buttonStyle(.glassProminent.shadow(false))
            .tint(accentColor)
            #if os(iOS)
            .controlSize(.large)
            #endif
            .frame(maxHeight: 75)
            .disabled(url.isEmpty)
        }
    }

    // MARK: - Found Servers

    private var foundServerButtons: some View {
        ForEach(viewModel.foundServers) { foundServer in
            FoundServerButton(foundServer: foundServer) {
                url = foundServer.server.currentURL.absoluteString
                viewModel.connect(url: url)
            }
            .focused($focusedServerID, equals: foundServer.id)
        }
    }

    #if os(iOS)
    private var localServersSection: some View {
        Section(L10n.localServers) {
            if viewModel.foundServers.isEmpty {
                Text(L10n.noLocalServersFound)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                foundServerButtons
            }
        }
    }
    #endif

    #if os(tvOS)
    // Servers on this network, and the family server through Tailscale, without typing an address
    private var automaticSection: some View {
        Section(L10n.servers) {
            if viewModel.foundServers.isNotEmpty {
                foundServerButtons
            } else if viewModel.hasSearched {
                VStack(spacing: 12) {
                    Text(L10n.noServersFound)
                        .font(.callout)
                        .fontWeight(.semibold)

                    // Tailscale only helps when the build knows an address to try through it
                    Text(FamilyServer.addresses.isEmpty ? L10n.noServersFoundHint : L10n.noServersFoundTailscaleHint)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
            } else {
                HStack(spacing: 20) {
                    ProgressView()

                    Text(L10n.lookingForServers)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
            }
        }
    }

    // Lands on the first server found, once, unless the user has already moved on to something else
    private func focusFirstServer() {
        guard !hasFocusedFirstServer,
              mode == .automatic,
              focusedServerID == nil,
              let firstServer = viewModel.foundServers.first
        else { return }

        hasFocusedFirstServer = true
        focusedServerID = firstServer.id
    }
    #endif

    private var contentView: some View {
        #if os(iOS)
        List {
            connectSection

            localServersSection
        }
        .toolbarTitleDisplayMode(.inline)
        .navigationBarCloseButton(disabled: viewModel.state == .connecting) {
            router.dismiss()
        }
        #else
        VStack(spacing: 60) {
            Picker(L10n.connectToServer, selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { mode in
                    Text(mode.displayTitle)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 560)

            VStack(alignment: .leading, spacing: 22) {
                switch mode {
                case .automatic:
                    automaticSection
                case .manual:
                    connectSection
                }
            }
            .frame(width: 860)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .edgePadding(.vertical)
        .loginWindowToolbar(isLoading: viewModel.state == .connecting)
        .onChange(of: viewModel.foundServers) {
            focusFirstServer()
        }
        #endif
    }

    // MARK: - Body

    var body: some View {
        contentView
            .navigationTitle(L10n.connect)
            .interactiveDismissDisabled(viewModel.state == .connecting)
            .onFirstAppear {
                isURLFocused = true
                viewModel.searchForServers()
            }
            .onReceive(timer) { _ in
                guard viewModel.state != .connecting else { return }

                viewModel.searchForServers()
            }
            .onReceive(viewModel.events, perform: onEvent)
            .topBarTrailing {
                if viewModel.state == .connecting {
                    ProgressView()
                }
            }
            .sheet(item: $duplicateServer) { server in
                DuplicateServerConnectionView(server: server) {
                    viewModel.addConnection(serverState: server)
                    duplicateServer = nil
                    router.dismiss()
                }
            }
            .errorMessage($viewModel.error)
    }
}
