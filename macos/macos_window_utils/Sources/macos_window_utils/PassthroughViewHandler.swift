//
//  PassthroughViewHandler.swift
//  macos_window_utils
//
//  Created by Adrian Samoticha on 22.12.24.
//

import Foundation

import FlutterMacOS

class PassthroughViewHandler {
  private var mainFlutterWindow: NSWindow?
  private var toolbarPassthroughContainer: NSView?
  private var toolbarPassthroughViews: [String: PassthroughView] = [:]
  
  static func create() -> PassthroughViewHandler {
    return PassthroughViewHandler();
  }
  
  func start(mainFlutterWindow: NSWindow) {
    self.mainFlutterWindow = mainFlutterWindow
    
    // Clean up necessary for flutter hot restart
    for entry in self.toolbarPassthroughViews {
      self.removeToolbarPassthroughView(id: entry.key)
    }
    self.toolbarPassthroughViews.removeAll()
    self.toolbarPassthroughContainer = nil
    
    // Get the count of accessory view controllers
    let accessoryCount = mainFlutterWindow.titlebarAccessoryViewControllers.count
    
    // Iterate through the indices in reverse order to avoid index shifting
    for index in stride(from: accessoryCount - 1, through: 0, by: -1) {
      mainFlutterWindow.removeTitlebarAccessoryViewController(at: index)
    }
  }
  
  func updateToolbarPassthroughView(id: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, enableDebugLayers: Bool, flutterViewController: NSViewController) {
    DispatchQueue.main.async {
      guard let window = self.mainFlutterWindow else {
        return
      }

      guard self.isValidFrame(x: x, y: y, width: width, height: height) else {
        self.removeToolbarPassthroughViewOnMainThread(id: id)
        return
      }
      
      if self.toolbarPassthroughContainer == nil {
        // Initialize the view if it is nil
        let accessoryViewController = NSTitlebarAccessoryViewController()
        accessoryViewController.layoutAttribute = .top
        
        self.toolbarPassthroughContainer = NSView()
        if (enableDebugLayers) {
          self.toolbarPassthroughContainer!.wantsLayer = true
          self.toolbarPassthroughContainer!.layer?.backgroundColor = NSColor.yellow.withAlphaComponent(0.2).cgColor
        }
        self.toolbarPassthroughContainer!.translatesAutoresizingMaskIntoConstraints = false
        
        // Assign the custom view to the accessory view controller
        accessoryViewController.view = self.toolbarPassthroughContainer!
        
        // Add the accessory view controller to the window
        window.addTitlebarAccessoryViewController(accessoryViewController)
      }
      
      if let containerView = self.toolbarPassthroughContainer {
        let windowHeight = window.frame.height
        
        // Convert Flutter coordinates to macOS coordinates
        let macY = windowHeight - y - height
        guard macY.isFinite else {
          self.removeToolbarPassthroughViewOnMainThread(id: id)
          return
        }
        
        let flutterToggleInvertedPosition = CGRect(x: x, y: macY, width: width, height: height)
        let frame = containerView.convert(flutterToggleInvertedPosition, from: nil)
        guard self.isValidFrame(frame) else {
          self.removeToolbarPassthroughViewOnMainThread(id: id)
          return
        }
        
        var view: PassthroughView
        if let existingView = self.toolbarPassthroughViews[id] {
          view = existingView
          view.frame = frame
        } else {
          view = PassthroughView(frame: frame, flutterViewController:flutterViewController)
          if (enableDebugLayers) {
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.green.withAlphaComponent(0.2).cgColor
            
          }
          
          // Add the view to the containerView
          containerView.addSubview(view)
          self.toolbarPassthroughViews[id] = view
        }
      }
    }
  }
  
  func removeToolbarPassthroughView(id: String) {
    DispatchQueue.main.async {
      self.removeToolbarPassthroughViewOnMainThread(id: id)
    }
  }

  private func removeToolbarPassthroughViewOnMainThread(id: String) {
    if let view = self.toolbarPassthroughViews[id] {
      view.removeFromSuperview()
      self.toolbarPassthroughViews.removeValue(forKey: id)
    }
  }

  private func isValidFrame(_ frame: CGRect) -> Bool {
    return isValidFrame(
      x: frame.origin.x,
      y: frame.origin.y,
      width: frame.size.width,
      height: frame.size.height
    )
  }

  private func isValidFrame(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> Bool {
    return x.isFinite &&
      y.isFinite &&
      width.isFinite &&
      height.isFinite &&
      width >= 0 &&
      height >= 0
  }
}

class PassthroughView: NSView {
  var flutterViewController: NSViewController?
  
  required init(frame: CGRect, flutterViewController: NSViewController) {
    super.init(frame: frame)
    self.flutterViewController = flutterViewController
  }
  
  required init?(coder decoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  
  override func mouseDown(with event: NSEvent) {
    // `mouseDownCanMoveWindow` has no effect when the NSWindow’s
    // `titlebarAppearsTransparent` property is true. For this reason
    // it is necessary to temporarily make the window immovable when
    // the passthrough view is clicked.
    let oldIsMovableValue = window!.isMovable
    window!.isMovable = false
    defer {
      window!.isMovable = oldIsMovableValue
    }
    
    flutterViewController!.mouseDown(with: event)
  }
  
  override func mouseUp(with event: NSEvent) {
    flutterViewController!.mouseUp(with: event)
  }
  
  override func rightMouseUp(with event: NSEvent) {
    flutterViewController!.rightMouseUp(with: event)
  }
  
  override func rightMouseDown(with event: NSEvent) {
    flutterViewController!.rightMouseDown(with: event)
  }
  
  override var mouseDownCanMoveWindow: Bool {
    return false
  }
}
