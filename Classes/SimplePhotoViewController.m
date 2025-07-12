//
//  SimplePhotoViewController 2.h
//  SuperHFRplus
//
//  Created by Bruno ARENE on 08/04/2025.
//


#import "SimplePhotoViewController.h"
#import "ThemeColors.h"

@interface SimplePhotoViewController () <UIScrollViewDelegate>

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;

@end

@implementation SimplePhotoViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Créer une navigation bar

    self.view.backgroundColor = [UIColor blackColor];

    // Fond noir
    UIView *backgroundView = [[UIView alloc] initWithFrame:self.view.bounds];
    backgroundView.backgroundColor = [UIColor blackColor];
    backgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:backgroundView];

    // ScrollView pour zoom
    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.delegate = self;
    self.scrollView.minimumZoomScale = 1.0;
    self.scrollView.maximumZoomScale = 4.0;
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.scrollView];

    // ImageView
    int iHeaderHeight = 20;
    /*if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        iHeaderHeight = 65;
    }*/
    self.imageView = [[UIImageView alloc] initWithFrame:CGRectMake(self.scrollView.bounds.origin.x, self.scrollView.bounds.origin.y + iHeaderHeight, self.scrollView.bounds.size.width, self.scrollView.bounds.size.height-iHeaderHeight)];
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.userInteractionEnabled = YES;
    self.imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.scrollView addSubview:self.imageView];

    // Double-tap zoom
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    doubleTap.numberOfTapsRequired = 2;
    [self.scrollView addGestureRecognizer:doubleTap];

    // Spinner
    self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    self.activityIndicator.center = self.view.center;
    self.activityIndicator.hidesWhenStopped = YES;
    self.activityIndicator.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [self.view addSubview:self.activityIndicator];

    [self.activityIndicator startAnimating];

    /*
    UINavigationBar *navBar = [[UINavigationBar alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, [UIApplication sharedApplication].statusBarFrame.size.height)];

    // Créer un item avec bouton "Fermer"
    UINavigationItem *navItem = [[UINavigationItem alloc] initWithTitle:@""];
    UIBarButtonItem *closeButton = [[UIBarButtonItem alloc]
                                    initWithTitle:@"Retour"
                                    style:UIBarButtonItemStylePlain
                                    target:self
                                    action:@selector(closeModal)];
    navItem.leftBarButtonItem = closeButton;
     [navBar setItems:@[navItem]];
     navBar.backgroundColor = [ThemeColors navBackgroundColor];
     [self.view addSubview:navBar];

     */

    self.view.backgroundColor = [UIColor blackColor];

    // Bouton de fermeture
    UIBarButtonItem *closeButton = [[UIBarButtonItem alloc]
                                    initWithTitle:@"Retour"
                                    style:UIBarButtonItemStylePlain
                                    target:self
                                    action:@selector(closeModal)];
    self.navigationItem.leftBarButtonItem = closeButton;
    
    [self loadImageFromURL:self.imageURL];
}

- (void)closeModal {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Zoom Gesture

- (void)handleDoubleTap:(UITapGestureRecognizer *)gesture {
    CGFloat newZoomScale = (self.scrollView.zoomScale == 1.0) ? 2.0 : 1.0;

    CGPoint tapPoint = [gesture locationInView:self.imageView];
    CGSize scrollViewSize = self.scrollView.bounds.size;

    CGFloat width = scrollViewSize.width / newZoomScale;
    CGFloat height = scrollViewSize.height / newZoomScale;
    CGFloat x = tapPoint.x - (width / 2.0);
    CGFloat y = tapPoint.y - (height / 2.0);

    CGRect zoomRect = CGRectMake(x, y, width, height);
    [self.scrollView zoomToRect:zoomRect animated:YES];
}

#pragma mark - Image loading

- (void)loadImageFromURL:(NSURL *)url {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"https://forum.hardware.fr" forHTTPHeaderField:@"Referer"];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:request
          completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
              dispatch_async(dispatch_get_main_queue(), ^{
                  [self.activityIndicator stopAnimating];

                  if (data && !error) {
                      UIImage *image = [UIImage imageWithData:data];
                      if (image) {
                          self.imageView.image = image;
                      } else {
                          [self showPlaceholderImage];
                      }
                  } else {
                      [self showPlaceholderImage];
                  }
              });
          }];
    [task resume];
}

- (void)showPlaceholderImage {
    UIImage *placeholder = [UIImage imageNamed:@"error_placeholder"];

    // Si pas d’image dans les assets, on crée une croix rouge simple
    if (!placeholder) {
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(100, 100), NO, 0);
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        CGContextSetStrokeColorWithColor(ctx, [UIColor redColor].CGColor);
        CGContextSetLineWidth(ctx, 10);
        CGContextMoveToPoint(ctx, 0, 0);
        CGContextAddLineToPoint(ctx, 100, 100);
        CGContextMoveToPoint(ctx, 100, 0);
        CGContextAddLineToPoint(ctx, 0, 100);
        CGContextStrokePath(ctx);
        placeholder = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }

    self.imageView.image = placeholder;
}

#pragma mark - ScrollView Zoom

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return self.imageView;
}

@end
