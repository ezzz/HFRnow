extension MessageListModel {
    /// What the pager's page menu asks for (#968): the steps are the arrows' own moves (the next page searches on in a split list
    /// whose segment is empty there, LOT-171), « Première page », « Dernière page » and a typed page are exactly that page.
    func perform(_ jump: PagerJump) async {
        switch jump {
        case .first: await goToFirstPage()
        case .previous: await goToPreviousPage()
        case .next: await goToNextPage()
        case .last: await goToLastPage()
        case .page(let page): await goToPage(page)
        }
    }
}
