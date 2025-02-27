import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: FramerSettings
    @State private var availableFonts: [String] = []
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Border Style")) {
                    Picker("Style", selection: $settings.borderStyle) {
                        ForEach(BorderStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: settings.borderStyle) { _ in
                        settings.resetToDefaults()
                    }
                }
                
                Section(header: Text("Border Settings")) {
                    VStack(alignment: .leading) {
                        Text("Border Thickness: \(Int(settings.borderThickness))")
                        Slider(value: $settings.borderThickness, in: 1...100, step: 1)
                    }
                    
                    ColorPicker("Border Color", selection: $settings.borderColor)
                    
                    VStack(alignment: .leading) {
                        Text("Padding: \(Int(settings.padding))")
                        Slider(value: $settings.padding, in: 0...300, step: 1)
                    }
                }
                
                Section(header: Text("Caption")) {
                    TextField("Custom Caption", text: $settings.caption)
                    
                    Toggle("Use Photo Date", isOn: $settings.useExifDate)
                        .onChange(of: settings.useExifDate) { newValue in
                            if newValue {
                                settings.caption = ""
                            }
                        }
                    
                    VStack(alignment: .leading) {
                        Text("Font Size: \(Int(settings.fontSize))")
                        Slider(value: $settings.fontSize, in: 10...80, step: 1)
                    }
                    
                    ColorPicker("Font Color", selection: $settings.fontColor)
                    
                    NavigationLink(destination: FontPickerView(selectedFont: $settings.fontName)) {
                        HStack {
                            Text("Font")
                            Spacer()
                            Text(FontManager.getDisplayName(for: settings.fontName))
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                if settings.borderStyle == .instagram {
                    Section(header: Text("Instagram Settings")) {
                        VStack(alignment: .leading) {
                            Text("Max Size: \(Int(settings.instagramMaxSize))")
                            Slider(value: $settings.instagramMaxSize, in: 500...1500, step: 10)
                        }
                    }
                }
                
                Section {
                    Button("Reset to Defaults") {
                        settings.resetToDefaults()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Frame Settings")
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
            .onAppear {
                availableFonts = FontManager.getAvailableFonts()
            }
        }
    }
}

struct FontPickerView: View {
    @Binding var selectedFont: String
    @Environment(\.presentationMode) var presentationMode
    @State private var searchText = ""
    
    var fonts: [String] {
        let allFonts = FontManager.getAvailableFonts()
        if searchText.isEmpty {
            return allFonts
        } else {
            return allFonts.filter { $0.lowercased().contains(searchText.lowercased()) }
        }
    }
    
    var body: some View {
        List {
            SearchBar(text: $searchText)
                .listRowInsets(EdgeInsets())
            
            ForEach(fonts, id: \.self) { fontName in
                Button(action: {
                    selectedFont = fontName
                    presentationMode.wrappedValue.dismiss()
                }) {
                    HStack {
                        Text(FontManager.getDisplayName(for: fontName))
                            .font(Font.custom(fontName, size: 17))
                        
                        Spacer()
                        
                        if fontName == selectedFont {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
                .foregroundColor(.primary)
            }
        }
        .navigationTitle("Select Font")
    }
}

struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            
            TextField("Search", text: $text)
                .disableAutocorrection(true)
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
    }
}