using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using BorderMuse.Core;
using BorderMuse.Imaging.Windows;
using Microsoft.UI;
using Microsoft.UI.Input;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Markup;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage;
using Windows.Storage.Pickers;
using Windows.Storage.Streams;
using Windows.System;

namespace BorderMuse.Windows;

public sealed partial class MainWindow : Window
{
    private readonly ImageProcessor processor = new();
    private readonly PhotoSession session;
    private readonly Grid root = new() { Language = "en-US", KeyboardAcceleratorPlacementMode = KeyboardAcceleratorPlacementMode.Hidden };
    private readonly Grid stage = new();
    private readonly Border paper = new() { Background = new SolidColorBrush(Colors.White), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
    private readonly Canvas photoCanvas = new();
    private readonly Image photoImage = new() { Stretch = Stretch.Fill };
    private readonly TextBlock previewMessage = Text("", 14);
    private readonly StackPanel empty = new() { Spacing = 14, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
    private readonly ListView filmstrip = new() { SelectionMode = ListViewSelectionMode.Single, Height = 108 };
    private readonly ObservableCollection<PhotoItem> items = [];
    private readonly Dictionary<Guid, PhotoItem> itemIndex = new();
    private IReadOnlyList<Preset>? displayedPresets;
    private int refreshQueued;
    private readonly TextBlock filename = Text("", 14), position = Text("", 12), scope = Text("", 12), status = Text("", 12), canvasSummary = Text("", 12), validation = Text("", 12);
    private readonly Button add = Button("addPhotos"), export = Button("exportMenu"), save = Button("savePresetShort"), cancel = Button("cancel"), reveal = Button("showFinder"), issues = Button("issuesTitle");
    private readonly ComboBox ratios = new() { HorizontalAlignment = HorizontalAlignment.Stretch }, presets = new() { HorizontalAlignment = HorizontalAlignment.Stretch };
    private readonly TextBox thickness = new() { Width = 64 }, longEdge = new() { Width = 92 }, quality = new() { Width = 64 };
    private readonly Slider slider = new() { Minimum = 0, Maximum = 50, StepFrequency = 1, SmallChange = 1 };
    private readonly ComboBox photoSize = new() { Width = 158, DisplayMemberPath = nameof(SizeChoice.Name) };
    private readonly CheckBox metadata = new() { Content = Strings.Text("metadata") };
    private readonly ProgressBar progress = new() { Minimum = 0, Maximum = 1 };
    private readonly TextBlock progressLabel = Text("", 12), sizeSummary = Text("", 12), metadataSummary = Text("", 12);
    private readonly StackPanel progressPanel = new() { Spacing = 8 }, inspectorFields = new() { Spacing = 10 };
    private readonly TextBlock resizeHelp = Text(Strings.Text("sizeBeforeBorder"), 12);
    private readonly ScrollViewer inspectorScroll = new() { HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
    private readonly Grid longEdgeRow = new();
    private readonly Expander options = new() { Header = Strings.Text("exportOptions"), HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Stretch };
    private readonly MenuFlyoutItem deletePreset = new() { Text = Strings.Text("deletePreset") };
    private readonly SemaphoreSlim decodeGate = new(1);
    private readonly Dictionary<string, BitmapImage> thumbnailCache = new();
    private string? previewKey;
    private int previewRevision;
    private bool updating, allowClose, showingQuit;
    private static TextBlock Text(string value, int size) => new() { Text = value, FontSize = size, TextWrapping = TextWrapping.Wrap };
    private static Button Button(string key) => new() { Content = Strings.Text(key) };
    private static void Id(DependencyObject target, string id, string? name = null)
    {
        AutomationProperties.SetAutomationId(target, id);
        if (name is not null)
            AutomationProperties.SetName(target, name);
    }
    private static Grid Row(FrameworkElement left, FrameworkElement right)
    {
        var grid = new Grid() { ColumnSpacing = 12 };
        grid.ColumnDefinitions.Add(new()
        {
            Width = new GridLength(1, GridUnitType.Star)
        });
        grid.ColumnDefinitions.Add(new()
        {
            Width = GridLength.Auto
        });
        grid.Children.Add(left);
        Grid.SetColumn(right, 1);
        grid.Children.Add(right);
        return grid;
    }
    private static StackPanel Group(params UIElement[] children)
    {
        var group = new StackPanel { Spacing = 6 };
        foreach (var child in children) group.Children.Add(child);
        return group;
    }
    private static Border Divider() => new() { Height = 1, Style = (Style)Application.Current.Resources["WorkspaceDividerStyle"], Margin = new Thickness(0, 4, 0, 4) };
    public MainWindow()
    {
        Title = Strings.Text("appName");
        string? smokeDirectory = Environment.GetEnvironmentVariable("BORDERMUSE_SMOKE_DIR");
        string presetPath = smokeDirectory is null ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "BorderMuse", "presets-v1.json") : Path.Combine(smokeDirectory, "presets-v1.json");
        session = new PhotoSession(processor, new PresetStore(presetPath));
        session.Changed += () => { if (Interlocked.Exchange(ref refreshQueued, 1) == 0) DispatcherQueue.TryEnqueue(() => { Interlocked.Exchange(ref refreshQueued, 0); Refresh(); }); };
        AppWindow.Resize(new global::Windows.Graphics.SizeInt32(1120, 800));
        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.PreferredMinimumWidth = 980;
            presenter.PreferredMinimumHeight = 680;
        }
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.ico"));
        AppWindow.Closing += Closing;
        Build();
        Content = root;
        root.Style = (Style)Application.Current.Resources["WorkspaceStyle"];
        stage.Style = (Style)Application.Current.Resources["PreviewStageStyle"];
        previewMessage.Style = (Style)Application.Current.Resources["PreviewMessageStyle"];
        validation.Style = (Style)Application.Current.Resources["ValidationStyle"];
        SyncSettings();
        Refresh();
    }
    private void Build()
    {
        root.RowDefinitions.Add(new()
        {
            Height = GridLength.Auto
        });
        root.RowDefinitions.Add(new()
        {
            Height = new GridLength(1, GridUnitType.Star)
        });
        root.RowDefinitions.Add(new()
        {
            Height = GridLength.Auto
        });
        var toolbar = Row(BuildMenu(), add);
        toolbar.Padding = new Thickness(12, 6, 16, 6);
        root.Children.Add(toolbar);
        add.Click += async (_, _) => await AddPhotos();
        Id(add, "addPhotosToolbar", Strings.Text("addPhotos"));
        var body = new Grid();
        body.ColumnDefinitions.Add(new()
        {
            Width = new GridLength(1, GridUnitType.Star)
        });
        body.ColumnDefinitions.Add(new()
        {
            Width = new GridLength(320)
        });
        Grid.SetRow(body, 1);
        root.Children.Add(body);
        var workspace = new Grid();
        workspace.RowDefinitions.Add(new()
        {
            Height = GridLength.Auto
        });
        workspace.RowDefinitions.Add(new()
        {
            Height = new GridLength(1, GridUnitType.Star)
        });
        workspace.RowDefinitions.Add(new()
        {
            Height = GridLength.Auto
        });
        body.Children.Add(workspace);
        filename.TextTrimming = TextTrimming.CharacterEllipsis;
        filename.MaxLines = 1;
        position.TextWrapping = TextWrapping.NoWrap;
        var heading = Row(filename, position);
        heading.Padding = new Thickness(24, 14, 24, 14);
        workspace.Children.Add(heading);
        Id(filename, "previewFilename");
        Grid.SetRow(stage, 1);
        workspace.Children.Add(stage);
        stage.AllowDrop = true;
        stage.DragOver += DragOver;
        stage.Drop += Drop;
        paper.Child = photoCanvas;
        photoCanvas.Children.Add(photoImage);
        stage.Children.Add(paper);
        stage.Children.Add(previewMessage);
        previewMessage.HorizontalAlignment = HorizontalAlignment.Center;
        previewMessage.VerticalAlignment = VerticalAlignment.Center;
        previewMessage.MaxWidth = 340;
        empty.Children.Add(new SymbolIcon(Symbol.Pictures));
        empty.Children.Add(Text(Strings.Text("emptyTitle"), 23));
        empty.Children.Add(Text(Strings.Text("emptySubtitle"), 14));
        var emptyAdd = Button("addPhotos");
        emptyAdd.HorizontalAlignment = HorizontalAlignment.Center;
        emptyAdd.Click += async (_, _) => await AddPhotos();
        empty.Children.Add(emptyAdd);
        empty.Children.Add(Text(Strings.Text("formats"), 12));
        stage.Children.Add(empty);
        stage.SizeChanged += (_, _) => LayoutPreview();
        Id(photoImage, "exportPreview");
        Id(emptyAdd, "addPhotosEmpty");
        filmstrip.ItemsSource = items;
        filmstrip.ItemsPanel = (ItemsPanelTemplate)XamlReader.Load("<ItemsPanelTemplate xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'><ItemsStackPanel Orientation='Horizontal'/></ItemsPanelTemplate>");
        filmstrip.ItemTemplate = (DataTemplate)XamlReader.Load("<DataTemplate xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'><Grid Width='88' Height='76' Padding='5' ToolTipService.ToolTip='{Binding Name}' AutomationProperties.Name='{Binding AccessibleName}'><Image Source='{Binding Thumbnail}' Stretch='Uniform'/></Grid></DataTemplate>");
        ScrollViewer.SetHorizontalScrollMode(filmstrip, ScrollMode.Auto);
        ScrollViewer.SetHorizontalScrollBarVisibility(filmstrip, ScrollBarVisibility.Auto);
        ScrollViewer.SetVerticalScrollMode(filmstrip, ScrollMode.Disabled);
        filmstrip.SelectionChanged += (_, _) => { if (!updating && filmstrip.SelectedItem is PhotoItem item) session.Select(item.Id); };
        filmstrip.KeyDown += (_, e) => { if (e.Key == VirtualKey.Left || e.Key == VirtualKey.Right) { session.SelectNeighbor(e.Key == VirtualKey.Right ? 1 : -1); e.Handled = true; } else if (e.Key == VirtualKey.Delete && session.Selected is { } photo) { session.Remove(photo.Id); e.Handled = true; } };
        filmstrip.ContainerContentChanging += async (_, e) =>
        {
            if (e.Item is not PhotoItem item)
                return;
            item.IsRealized = !e.InRecycleQueue;
            if (e.InRecycleQueue)
            {
                item.Thumbnail = null;
                return;
            }
            var remove = new MenuFlyoutItem() { Text = Strings.Text("remove") };
            var container = e.ItemContainer;
            container.Tag = item.Id;
            remove.Click += (_, _) => { if (container.Tag is Guid id) session.Remove(id); };
            var menu = new MenuFlyout();
            menu.Items.Add(remove);
            container.ContextFlyout = menu;
            Id(container, "photo-" + item.Name, item.AccessibleName);
            await Thumbnail(item);
        };
        filmstrip.Padding = new Thickness(16, 8, 16, 8);
        Grid.SetRow(filmstrip, 2);
        workspace.Children.Add(filmstrip);
        Id(filmstrip, "photos", Strings.Text("photos"));
        AutomationProperties.SetHelpText(filmstrip, Strings.Text("photosKeyboardHelp"));
        var inspector = BuildInspector();
        Grid.SetColumn(inspector, 1);
        body.Children.Add(inspector);
        var footer = new StackPanel() { Orientation = Orientation.Horizontal, Spacing = 16 };
        footer.Children.Add(status);
        footer.Children.Add(reveal);
        footer.Children.Add(issues);
        reveal.Click += (_, _) => { if (session.Result is { } result) Shell.Reveal(result.Outputs); };
        issues.Click += async (_, _) => await ShowIssues();
        var bottom = Row(footer, canvasSummary);
        bottom.Padding = new Thickness(20, 10, 20, 10);
        Grid.SetRow(bottom, 2);
        root.Children.Add(bottom);
        Id(status, "exportStatus");
        Id(reveal, "showFinder");
        Id(issues, "reviewIssues");
        var openKey = new KeyboardAccelerator() { Key = VirtualKey.O, Modifiers = VirtualKeyModifiers.Control };
        openKey.Invoked += async (_, e) => { await AddPhotos(); e.Handled = true; };
        root.KeyboardAccelerators.Add(openKey);
        var exportKey = new KeyboardAccelerator() { Key = VirtualKey.E, Modifiers = VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift };
        exportKey.Invoked += async (_, e) => { await ChooseExport(); e.Handled = true; };
        root.KeyboardAccelerators.Add(exportKey);
        var cancelKey = new KeyboardAccelerator() { Key = VirtualKey.Escape };
        cancelKey.Invoked += (_, e) => { if (session.IsExporting && !showingQuit) { session.CancelExport(); e.Handled = true; } };
        root.KeyboardAccelerators.Add(cancelKey);
    }
    private MenuBar BuildMenu()
    {
        var menu = new MenuBar();
        var file = new MenuBarItem() { Title = Strings.Text("fileMenu") };
        menu.Items.Add(file);
        MenuFlyoutItem Add(string key, Func<Task> action)
        {
            var item = new MenuFlyoutItem() { Text = Strings.Text(key) };
            item.Click += async (_, _) => await action();
            return item;
        }
        file.Items.Add(Add("addPhotos", AddPhotos));
        file.Items.Add(Add("exportMenu", () => ChooseExport()));
        file.Items.Add(Add("clear", () => { session.Clear(); return Task.CompletedTask; }));
        file.Items.Add(new MenuFlyoutSeparator());
        file.Items.Add(Add("quit", RequestCloseAsync));
        var help = new MenuBarItem() { Title = Strings.Text("helpMenu") };
        var about = Add("about", async () => await Dialog(Strings.Text("appName"), Text(Strings.Text("aboutVersion"), 14), "done"));
        help.Items.Add(about);
        menu.Items.Add(help);
        return menu;
    }
    private FrameworkElement BuildInspector()
    {
        var inspector = new Grid() { Padding = new Thickness(22) };
        inspector.RowDefinitions.Add(new()
        {
            Height = new GridLength(1, GridUnitType.Star)
        });
        inspector.RowDefinitions.Add(new()
        {
            Height = GridLength.Auto
        });
        inspectorScroll.Content = inspectorFields;
        inspector.Children.Add(inspectorScroll);
        var heading = Group(Text(Strings.Text("borderSettings"), 16), scope);
        heading.Spacing = 4;
        inspectorFields.Children.Add(heading);
        save.Click += async (_, _) => await SavePreset();
        var presetHeading = Row(Text(Strings.Text("preset"), 14), save);
        Id(save, "savePreset");
        var more = new Button() { Content = new SymbolIcon(Symbol.More) };
        Id(more, "presetActions", Strings.Text("presetActions"));
        var presetMenu = new MenuFlyout();
        presetMenu.Items.Add(deletePreset);
        more.Flyout = presetMenu;
        deletePreset.Click += async (_, _) => { try { session.DeletePreset(); } catch { await Dialog(Strings.Text("issuesTitle"), Text(Strings.Text("presetError"), 14), "done"); } };
        inspectorFields.Children.Add(Group(presetHeading, Row(presets, more)));
        presets.SelectionChanged += (_, _) => { if (!updating && presets.SelectedItem is PresetChoice choice) { session.UsePreset(choice.Id); SyncSettings(); } };
        Id(presets, "presetPicker", Strings.Text("preset"));
        ratios.ItemsSource = new[] { "original", "1:1", "5:4", "4:5", "3:2", "2:3", "16:9", "9:16", "2:1", "1:2" }.Select(r => new RatioChoice(r, r == "original" ? Strings.Text("original") : r)).ToArray();
        ratios.DisplayMemberPath = nameof(RatioChoice.Name);
        inspectorFields.Children.Add(Group(Text(Strings.Text("ratio"), 14), ratios));
        ratios.SelectionChanged += (_, _) => ApplySettings();
        Id(ratios, "ratioPicker", Strings.Text("ratio"));
        slider.Height = slider.MinHeight = 32;
        inspectorFields.Children.Add(Group(Row(Text(Strings.Text("thickness"), 14), thickness), slider));
        Id(thickness, "thicknessField", Strings.Text("thickness"));
        Id(slider, "thicknessSlider", Strings.Text("thickness"));
        AutomationProperties.SetHelpText(thickness, Strings.Text("thicknessError"));
        thickness.TextChanged += (_, _) => ApplySettings();
        slider.ValueChanged += (_, e) => { if (!updating) thickness.Text = ((int)Math.Round(e.NewValue)).ToString(Strings.Culture); };
        Id(validation, "settingsError");
        var settings = new StackPanel() { Spacing = 8 };
        photoSize.ItemsSource = new[] { new SizeChoice(0, Strings.Text("original")), new SizeChoice(2048, Strings.Text("size2048")), new SizeChoice(-1, Strings.Text("custom")) };
        settings.Children.Add(Row(Text(Strings.Text("photoSize"), 14), photoSize));
        Id(photoSize, "photoSizePicker", Strings.Text("photoSize"));
        AutomationProperties.SetHelpText(photoSize, Strings.Text("sizeHelp"));
        ToolTipService.SetToolTip(photoSize, Strings.Text("sizeHelp"));
        longEdgeRow.ColumnDefinitions.Add(new()
        {
            Width = new GridLength(1, GridUnitType.Star)
        });
        longEdgeRow.ColumnDefinitions.Add(new()
        {
            Width = GridLength.Auto
        });
        longEdgeRow.Children.Add(Text(Strings.Text("longEdge"), 14));
        Grid.SetColumn(longEdge, 1);
        longEdgeRow.Children.Add(longEdge);
        settings.Children.Add(longEdgeRow);
        settings.Children.Add(resizeHelp);
        settings.Children.Add(Row(Text(Strings.Text("quality"), 14), quality));
        settings.Children.Add(metadata);
        settings.Children.Add(Text(Strings.Text("metadataHelp"), 12));

        options.Content = settings;
        inspectorFields.Children.Add(options);
        photoSize.SelectionChanged += (_, _) =>
        {
            if (updating) return;
            if (photoSize.SelectedItem is SizeChoice choice && choice.LongEdge != 0)
            {
                updating = true;
                longEdge.Text = (choice.LongEdge == 2048 ? 2048 : session.Settings.LongEdge).ToString(Strings.Culture);
                updating = false;
            }
            ApplySettings();
        };
        metadata.Checked += (_, _) => ApplySettings();
        metadata.Unchecked += (_, _) => ApplySettings();
        longEdge.TextChanged += (_, _) => ApplySettings();
        quality.TextChanged += (_, _) => ApplySettings();
        Id(longEdge, "longEdgeField", Strings.Text("longEdge"));
        Id(quality, "qualityField", Strings.Text("quality"));
        AutomationProperties.SetHelpText(longEdge, Strings.Text("longEdgeError"));
        AutomationProperties.SetHelpText(quality, Strings.Text("qualityError"));
        var footer = new StackPanel() { Spacing = 8, Padding = new Thickness(0, 12, 0, 0) };
        footer.Children.Add(validation);
        footer.Children.Add(Row(sizeSummary, metadataSummary));
        ToolTipService.SetToolTip(sizeSummary, Strings.Text("formatHelp"));
        footer.Children.Add(Divider());
        progressPanel.Children.Add(progress);
        progressPanel.Children.Add(Row(progressLabel, cancel));
        footer.Children.Add(progressPanel);
        cancel.Click += (_, _) => session.CancelExport();
        Id(cancel, "cancelExport");
        export.HorizontalAlignment = HorizontalAlignment.Stretch;
        export.HorizontalContentAlignment = HorizontalAlignment.Center;
        export.Click += async (_, _) => await ChooseExport();
        footer.Children.Add(export);
        Id(export, "exportButton");
        AutomationProperties.SetHelpText(export, Strings.Text("formatHelp"));
        Grid.SetRow(footer, 1);
        inspector.Children.Add(footer);
        return inspector;
    }
    private void ApplySettings()
    {
        if (updating)
            return;
        string? error = null;
        if (!int.TryParse(thickness.Text, out int t) || t is < 0 or > 50)
            error = Strings.Text("thicknessError");
        if (!int.TryParse(quality.Text, out int q) || q is < 1 or > 100)
            error ??= Strings.Text("qualityError");
        int choice = (photoSize.SelectedItem as SizeChoice)?.LongEdge ?? 0;
        int edge = choice == 2048 ? 2048 : session.Settings.LongEdge;
        if (choice == -1 && (!int.TryParse(longEdge.Text, out edge) || edge is < 1 or > 100_000))
            error ??= Strings.Text("longEdgeError");
        session.InputsValid = error is null;
        validation.Text = error ?? "";
        validation.Visibility = error is null ? Visibility.Collapsed : Visibility.Visible;
        if (error is null)
        {
            session.Settings = new BorderSettings() { Ratio = (ratios.SelectedItem as RatioChoice)?.Value ?? "original", Thickness = t, Quality = q, ReduceSize = choice != 0, LongEdge = edge, KeepMetadata = metadata.IsChecked == true };
            updating = true;
            slider.Value = t;
            updating = false;
        }
        longEdgeRow.Visibility = choice == -1 ? Visibility.Visible : Visibility.Collapsed;
        resizeHelp.Visibility = choice != 0 ? Visibility.Visible : Visibility.Collapsed;
        session.NotifySettingsChanged();
    }
    private void SyncSettings()
    {
        updating = true;
        var s = session.Settings;
        thickness.Text = s.Thickness.ToString(Strings.Culture);
        slider.Value = s.Thickness;
        quality.Text = s.Quality.ToString(Strings.Culture);
        longEdge.Text = s.LongEdge.ToString(Strings.Culture);
        photoSize.SelectedItem = photoSize.Items.Cast<SizeChoice>().First(c => c.LongEdge == (!s.ReduceSize ? 0 : s.LongEdge == 2048 ? 2048 : -1));
        metadata.IsChecked = s.KeepMetadata;
        ratios.SelectedItem = ratios.Items.Cast<RatioChoice>().First(r => r.Value == s.Ratio);
        longEdgeRow.Visibility = s.ReduceSize && s.LongEdge != 2048 ? Visibility.Visible : Visibility.Collapsed;
        resizeHelp.Visibility = s.ReduceSize ? Visibility.Visible : Visibility.Collapsed;
        options.IsExpanded = s.ReduceSize;
        validation.Text = "";
        validation.Visibility = Visibility.Collapsed;
        updating = false;
    }
    private void Refresh()
    {
        updating = true;
        var ids = session.Photos.Select(p => p.Id).ToHashSet();
        foreach (var old in items.Where(i => !ids.Contains(i.Id)).ToArray())
        {
            items.Remove(old);
            itemIndex.Remove(old.Id);
        }
        foreach (var photo in session.Photos)
        {
            if (!itemIndex.TryGetValue(photo.Id, out var item))
            {
                item = new PhotoItem(photo);
                itemIndex.Add(photo.Id, item);
                items.Add(item);
            }
            else if (item.Photo.Info.Version != photo.Info.Version)
            {
                item.Photo = photo;
                item.Thumbnail = null;
                if (item.IsRealized)
                    _ = Thumbnail(item);
            }
        }
        var selectedItem = session.SelectedId is { } selectedId ? itemIndex.GetValueOrDefault(selectedId) : null;
        if (!ReferenceEquals(filmstrip.SelectedItem, selectedItem))
        {
            filmstrip.SelectedItem = selectedItem;
            if (selectedItem is not null)
                filmstrip.ScrollIntoView(selectedItem);
        }
        filmstrip.Visibility = items.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        empty.Visibility = items.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        paper.Visibility = items.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        filename.Text = session.Selected is { } p ? Path.GetFileName(p.Path) : "";
        ToolTipService.SetToolTip(filename, filename.Text);
        position.Text = session.Selected is { } p2 ? Strings.Format("position", session.Photos.FindIndex(p => p.Id == p2.Id) + 1, session.Photos.Count) : "";
        scope.Text = items.Count == 0 ? Strings.Text("batchEmpty") : items.Count == 1 ? Strings.Text("batchOne") : Strings.Format("batchAll", items.Count);
        if (!ReferenceEquals(displayedPresets, session.Presets))
        {
            displayedPresets = session.Presets;
            presets.ItemsSource = new[] { new PresetChoice(null, Strings.Text("custom")) }.Concat(session.Presets.Select(p => new PresetChoice(p.Id, p.Name))).ToArray();
            presets.DisplayMemberPath = nameof(PresetChoice.Name);
        }
        if (presets.SelectedItem is not PresetChoice selectedPreset || selectedPreset.Id != session.SelectedPreset)
            presets.SelectedItem = presets.Items.Cast<PresetChoice>().FirstOrDefault(p => p.Id == session.SelectedPreset);
        deletePreset.IsEnabled = session.SelectedPreset is not null;
        export.Content = items.Count == 0 ? Strings.Text("exportMenu") : items.Count == 1 ? Strings.Text("exportOne") : Strings.Format("export", items.Count);
        export.IsEnabled = session.CanExport;
        export.Visibility = session.IsExporting ? Visibility.Collapsed : Visibility.Visible;
        add.IsEnabled = !session.IsExporting;
        foreach (var control in new Control[] { presets, ratios, thickness, slider, options })
            control.IsEnabled = !session.IsExporting;
        deletePreset.IsEnabled = session.SelectedPreset is not null && !session.IsExporting;
        save.IsEnabled = session.InputsValid && !session.IsExporting;
        progressPanel.Visibility = session.IsExporting ? Visibility.Visible : Visibility.Collapsed;
        progress.Value = (double)Math.Max(0, session.Progress.Completed - 1) / Math.Max(1, session.Progress.Total);
        progressLabel.Text = Strings.Format("exporting", session.Progress.Completed, session.Progress.Total);
        sizeSummary.Text = session.Settings.ReduceSize ? Strings.Format("sizeLimit", session.Settings.LongEdge) : Strings.Text("originalResolution");
        metadataSummary.Text = Strings.Text(session.Settings.KeepMetadata ? "metadataKeptSummary" : "metadataRemovedSummary");
        status.Text = session.IsImporting ? Strings.Text("loading") : session.Result is { } result ? Strings.Format(result.Canceled ? "cancelled" : "complete", result.Outputs.Count) : session.Selected is { } selectedPhoto ? Strings.Format("contentSize", session.Settings.PreparedSize(selectedPhoto.Info.Size).Width, session.Settings.PreparedSize(selectedPhoto.Info.Size).Height) : "";
        reveal.Visibility = session.Result?.Outputs.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        issues.Visibility = session.Issues.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        issues.Content = Strings.Format("issues", session.Issues.Count);
        updating = false;
        LayoutPreview();
        _ = Preview();
    }
    private void LayoutPreview()
    {
        if (session.Layout is not { } layout)
            return;
        double scale = Math.Max(0, Math.Min((stage.ActualWidth - 72) / layout.Width, (stage.ActualHeight - 72) / layout.Height));
        paper.Width = layout.Width * scale;
        paper.Height = layout.Height * scale;
        photoCanvas.Width = paper.Width;
        photoCanvas.Height = paper.Height;
        photoImage.Width = (layout.Width - layout.Left - layout.Right) * scale;
        photoImage.Height = (layout.Height - layout.Top - layout.Bottom) * scale;
        Canvas.SetLeft(photoImage, layout.Left * scale);
        Canvas.SetTop(photoImage, layout.Top * scale);
        canvasSummary.Text = Strings.Format("canvasSize", layout.Width, layout.Height);
        AutomationProperties.SetName(photoImage, Strings.Format("previewSummary", filename.Text, Strings.Format("output", layout.Width, layout.Height)));
    }
    private async Task Preview()
    {
        var photo = session.Selected;
        string? key = photo?.Path + photo?.Info.Version.Sha256;
        if (key == previewKey)
            return;
        previewKey = key;
        int revision = ++previewRevision;
        photoImage.Source = null;
        if (photo is null)
        {
            previewMessage.Text = "";
            canvasSummary.Text = "";
            return;
        }
        previewMessage.Text = Strings.Text("loading");
        await decodeGate.WaitAsync();
        try
        {
            if (revision != previewRevision)
                return;
            var data = await Task.Run(() => processor.Preview(photo.Path, 1600, photo.Info.Version));
            if (revision != previewRevision)
                return;
            var image = await Bitmap(data);
            if (revision == previewRevision)
            {
                photoImage.Source = image;
                previewMessage.Text = "";
            }
        }
        catch (Exception error) { if (revision == previewRevision) previewMessage.Text = error is ImageException ? error.Message : Strings.Text("importError"); }
        finally { decodeGate.Release(); }
    }
    private async Task Thumbnail(PhotoItem item)
    {
        if (item.Thumbnail is not null)
            return;
        string key = item.Photo.Info.Version.Sha256;
        if (thumbnailCache.TryGetValue(key, out var cached))
        {
            item.Thumbnail = cached;
            return;
        }
        await decodeGate.WaitAsync();
        try
        {
            if (!item.IsRealized)
                return;
            var data = await Task.Run(() => processor.Preview(item.Photo.Path, 240, item.Photo.Info.Version));
            var image = await Bitmap(data);
            if (thumbnailCache.Count >= 128)
                thumbnailCache.Remove(thumbnailCache.Keys.First());
            thumbnailCache[key] = image;
            if (item.IsRealized)
                item.Thumbnail = image;
        }
        catch {/* Preview and export surface readable per-file errors. */}
        finally { decodeGate.Release(); }
    }
    private static async Task<BitmapImage> Bitmap(byte[] data)
    {
        using var stream = new InMemoryRandomAccessStream();
        using (var writer = new DataWriter(stream.GetOutputStreamAt(0)))
        {
            writer.WriteBytes(data);
            await writer.StoreAsync();
        }
        stream.Seek(0);
        var image = new BitmapImage();
        await image.SetSourceAsync(stream);
        return image;
    }
    public Task ImportAsync(IEnumerable<string> paths) => session.ImportAsync(paths);
    private async Task AddPhotos()
    {
        if (session.IsExporting)
            return;
        var picker = new FileOpenPicker();
        foreach (string type in new[] { ".jpg", ".jpeg", ".png", ".tif", ".tiff" })
            picker.FileTypeFilter.Add(type);
        WinRT.Interop.InitializeWithWindow.Initialize(picker, WinRT.Interop.WindowNative.GetWindowHandle(this));
        var files = await picker.PickMultipleFilesAsync();
        await session.ImportAsync(files.Select(f => f.Path));
    }
    private void DragOver(object sender, DragEventArgs e)
    {
        e.AcceptedOperation = !session.IsExporting && e.DataView.Contains(StandardDataFormats.StorageItems) ? DataPackageOperation.Copy : DataPackageOperation.None;
    }
    private async void Drop(object sender, DragEventArgs e)
    {
        if (session.IsExporting || !e.DataView.Contains(StandardDataFormats.StorageItems))
            return;
        var deferral = e.GetDeferral();
        try
        {
            var files = await e.DataView.GetStorageItemsAsync();
            await session.ImportAsync(files.OfType<StorageFile>().Select(f => f.Path));
        }
        finally { deferral.Complete(); }
    }
    private async Task ChooseExport(bool retry = false)
    {
        if (!session.CanExport)
            return;
        var picker = new FolderPicker() { CommitButtonText = Strings.Text("choose") };
        picker.FileTypeFilter.Add("*");
        WinRT.Interop.InitializeWithWindow.Initialize(picker, WinRT.Interop.WindowNative.GetWindowHandle(this));
        var folder = await picker.PickSingleFolderAsync();
        if (folder is not null)
            await session.ExportAsync(folder.Path, retry);
    }
    private async Task SavePreset()
    {
        var name = new TextBox() { PlaceholderText = Strings.Text("presetName") };
        Id(name, "presetName", Strings.Text("presetName"));
        var dialog = new ContentDialog() { XamlRoot = root.XamlRoot, Title = Strings.Text("savePreset"), Content = name, PrimaryButtonText = Strings.Text("save"), CloseButtonText = Strings.Text("cancel"), IsPrimaryButtonEnabled = false, DefaultButton = ContentDialogButton.Primary };
        name.TextChanged += (_, _) => dialog.IsPrimaryButtonEnabled = !string.IsNullOrWhiteSpace(name.Text);
        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
            try
            {
                session.SavePreset(name.Text);
            }
            catch { await Dialog(Strings.Text("issuesTitle"), Text(Strings.Text("presetError"), 14), "done"); }
    }
    private async Task ShowIssues()
    {
        var list = new StackPanel() { Spacing = 16 };
        foreach (var issue in session.Issues)
        {
            var row = new StackPanel() { Spacing = 4 };
            row.Children.Add(Text(Path.GetFileName(issue.Path), 14));
            row.Children.Add(Text(issue.Message, 12));
            list.Children.Add(row);
        }
        bool retry = session.Issues.Any(i => i.CanRetry);
        var dialog = new ContentDialog() { XamlRoot = root.XamlRoot, Title = Strings.Text("issuesTitle"), Content = new ScrollViewer() { Content = list, MaxHeight = 400 }, CloseButtonText = Strings.Text("done"), PrimaryButtonText = retry ? Strings.Text("retry") : "", IsPrimaryButtonEnabled = retry };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
            await ChooseExport(true);
    }
    private async Task Dialog(string title, UIElement content, string close) => await new ContentDialog() { XamlRoot = root.XamlRoot, Title = title, Content = content, CloseButtonText = Strings.Text(close) }.ShowAsync();
    private void Closing(AppWindow sender, AppWindowClosingEventArgs args)
    {
        if (allowClose || (!session.IsExporting && !showingQuit))
            return;
        args.Cancel = true;
        // Return from the native close event before presenting async XAML UI.
        DispatcherQueue.TryEnqueue(async () => await RequestCloseAsync());
    }
    private async Task RequestCloseAsync()
    {
        if (showingQuit) return;
        if (!session.IsExporting) { Close(); return; }
        showingQuit = true;
        try
        {
            var dialog = new ContentDialog() { XamlRoot = root.XamlRoot, Title = Strings.Text("closeTitle"), Content = Strings.Text("closeMessage"), PrimaryButtonText = Strings.Text("keepWorking"), SecondaryButtonText = Strings.Text("stopQuit"), DefaultButton = ContentDialogButton.Primary };
            if (await dialog.ShowAsync() == ContentDialogResult.Secondary)
            {
                await session.CancelExportAndWaitAsync();
                allowClose = true;
                Close();
            }
        }
        finally { showingQuit = false; }
    }
    private sealed record SizeChoice(int LongEdge, string Name);
    private sealed record RatioChoice(string Value, string Name);
    private sealed record PresetChoice(Guid? Id, string Name);
    private sealed class PhotoItem(Photo photo) : INotifyPropertyChanged
    {
        public Photo Photo { get; set; } = photo; public bool IsRealized
        {
            get; set;
        }
        public Guid Id => Photo.Id; public string Name => Path.GetFileName(Photo.Path); public string AccessibleName => Strings.Format("selectPhoto", Name);
        private BitmapImage? thumbnail; public BitmapImage? Thumbnail
        {
            get => thumbnail; set
            {
                thumbnail = value;
                PropertyChanged?.Invoke(this, new(nameof(Thumbnail)));
            }
        }
        public event PropertyChangedEventHandler? PropertyChanged;
    }
}
